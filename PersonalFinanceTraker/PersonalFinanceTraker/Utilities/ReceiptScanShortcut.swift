//
//  ReceiptScanShortcut.swift
//  PersonalFinanceTraker
//
//  Runs the entire "pick a source, capture/select, recognize, parse" flow from wherever the
//  "Scan receipt" shortcut lives (Dashboard, Activity, Insights, iPad sidebar) — never nested
//  inside the Add Transaction sheet's own presentation. Presenting a confirmationDialog or
//  fullScreenCover on a view controller that is itself still mid-presentation-transition is
//  unreliable in UIKit (worse on a cold start, when the transition is slower) — that's the exact
//  bug seen scanning from Dashboard: the dialog rendered corrupted the first time the app opened,
//  fine every time after. Running this on the shell's own already-settled view sidesteps the race
//  entirely instead of trying to out-time it. See docs/features/2026-08-27-scan-receipt-autofill.md.
//
//  The Add Transaction sheet only opens once a `ReceiptScan` is in hand — see
//  `EditAddTransactionView.initialReceiptScan`. The sheet's own in-form "Scan receipt" button
//  keeps its separate, simpler flow: that one is never racing a presentation, since the sheet
//  it's attached to is already fully on screen by the time the user can tap it.
//

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

private struct ReceiptScanShortcut: ViewModifier {
    @Binding var isPresented: Bool
    /// Widget entry point: no source dialog, straight to the camera.
    var directToCamera = false
    let onScanned: (ReceiptScan) -> Void

    @State private var showingDocumentScanner = false
    @State private var showingPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingCameraPermissionAlert = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Scan Receipt",
                isPresented: Binding(
                    get: { isPresented && !directToCamera },
                    set: { if !$0 { isPresented = false } }
                ),
                titleVisibility: .visible
            ) {
                Button("Take Photo") { requestCameraAccessThenScan() }
                Button("Choose Photo") { showingPhotoPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: isPresented) { _, wants in
                guard directToCamera, wants else { return }
                isPresented = false
                requestCameraAccessThenScan()
            }
            .alert(
                "Camera Access Needed",
                isPresented: $showingCameraPermissionAlert
            ) {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow camera access in Settings to scan a receipt, or choose a photo from your library instead.")
            }
            .fullScreenCover(isPresented: $showingDocumentScanner) {
                ReceiptCameraView { result in
                    showingDocumentScanner = false
                    switch result {
                    case .success(let images):
                        guard !images.isEmpty else { return } // user cancelled
                        processReceiptImages(images)
                    case .failure:
                        errorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
                    }
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task {
                    defer { photoPickerItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        errorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
                        return
                    }
                    processReceiptImages([image])
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("Reading receipt…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert(
                "Couldn't read this receipt",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func requestCameraAccessThenScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingDocumentScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingDocumentScanner = true
                    } else {
                        showingCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingCameraPermissionAlert = true
        @unknown default:
            showingCameraPermissionAlert = true
        }
    }

    private func processReceiptImages(_ images: [UIImage]) {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                ReceiptScanDebug.beginScan("shortcut")
                for image in images {
                    ReceiptScanDebug.log(step: "input", ReceiptScanDebug.describe(image))
                }
                let document = try await ReceiptTextRecognizer.recognize(in: images)
                ReceiptScanDebug.log(
                    step: "ocr",
                    "\(document.lines.count) lines, confidence \(document.meanConfidence), "
                    + "rows \(document.rows.count)"
                )
                guard !document.lines.isEmpty else {
                    errorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
                    return
                }
                let scan = ReceiptParser.parse(document)
                ReceiptScanDebug.log(
                    step: "parsed",
                    "total=\(String(describing: scan.total)) "
                    + "candidates=\(scan.totalCandidates) "
                    + "merchant=\(scan.merchant ?? "nil") "
                    + "date=\(String(describing: scan.date)) clamped=\(scan.dateWasClamped)"
                )
                // ponytail: temporary — a real miss (2026-08-28, "L'Autentica" receipt) needs
                // ground-truth Vision output to diagnose, not a guess at what the photo shows.
                // Remove once total accuracy is trusted enough to drop this (see
                // ReceiptParser's earlier debug-print precedent in this file's git history).
                if scan.total == nil && scan.totalCandidates.isEmpty {
                    print("ReceiptParser found no total. Recognized lines:")
                    for line in document.lines { print("  \"\(line)\"") }
                    print("Vision table rows:")
                    for row in document.rows { print("  \"\(row.label)\" -> \(row.amount)") }
                }
                onScanned(scan)
            } catch {
                errorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
            }
        }
    }
}

extension View {
    /// Attach once, high up the view hierarchy (the tab/shell root, not the Add Transaction
    /// sheet). Flip `isPresented` to true to show the source-choice dialog; `onScanned` fires
    /// once recognition + parsing succeed, with the sheet not open yet.
    func receiptScanShortcut(
        isPresented: Binding<Bool>,
        directToCamera: Bool = false,
        onScanned: @escaping (ReceiptScan) -> Void
    ) -> some View {
        modifier(ReceiptScanShortcut(isPresented: isPresented, directToCamera: directToCamera, onScanned: onScanned))
    }
}
