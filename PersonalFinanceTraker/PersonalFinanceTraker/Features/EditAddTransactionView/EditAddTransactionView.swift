//
//  TransactionView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData
import PhotosUI
import TipKit
import UIKit
import AVFoundation

private enum PendingRecurrenceAction {
    case save(TransactionInput)
    case delete
}

private enum RecurrenceEditScope {
    case thisOnly
    case thisAndFuture
}

struct EditAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataChangedSignal.self) private var dataChanged
    @State private var viewModel: EditAddTransactionViewModel
    @State private var pendingRecurrenceAction: PendingRecurrenceAction?
    @State private var showingDeleteConfirmation = false
    @State private var refocusToken = 0
    @State private var savedCount = 0
    @State private var showSavedToast = false
    @State private var didFocusOnAmount = false
    @State private var toastTask: Task<Void, Never>?
    private let materializationService: RecurrenceMaterializationService

    // MARK: - Receipt scan
    @State private var showingReceiptSourceDialog = false
    @State private var showingDocumentScanner = false
    @State private var showingPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isProcessingReceiptScan = false
    @State private var receiptScanErrorMessage: String?
    @State private var showingCameraPermissionAlert = false
    /// Set from `initialReceiptScan` and consumed once in `.onAppear` — lets the shell-level
    /// "Scan receipt" shortcut (ReceiptScanShortcut, run from Dashboard/Activity/Insights before
    /// this sheet even opens) hand off an already-parsed scan instead of this view driving its
    /// own capture. See ReceiptScanShortcut's header comment for why capture never starts here.
    @State private var pendingInitialScan: ReceiptScan?

    init(
        _ snapshot: TransactionSnapshot? = nil,
        draft: TransactionDraft? = nil,
        repo: any ITransactionRepository,
        materializationService: RecurrenceMaterializationService,
        // Lets RecurringView's "+" open this sheet with Repeat already on, matching the
        // context the user tapped it from. Add-mode only in practice — nothing sets this
        // alongside `snapshot`.
        presetRecurring: Bool = false,
        // Set when the "Scan receipt" shortcut next to "+ Add" already ran capture + recognition
        // before this sheet opened. Applied once in .onAppear, same tail as a scan started from
        // this sheet's own toolbar button.
        initialReceiptScan: ReceiptScan? = nil
    ) {
        let vm = EditAddTransactionViewModel(editingItem: snapshot, draft: draft, repo: repo, hasPendingReceiptScan: initialReceiptScan != nil)
        if presetRecurring { vm.isRecurring = true }
        _viewModel = State(wrappedValue: vm)
        self.materializationService = materializationService
        _pendingInitialScan = State(wrappedValue: initialReceiptScan)
    }

    var body: some View {
        TransactionFormView(viewModel: viewModel, focusTrigger: refocusToken)
        .readableWidth()
        .sensoryFeedback(.success, trigger: savedCount)
        .overlay(alignment: .top) {
            if showSavedToast {
                ToastBanner(icon: "checkmark.circle.fill", message: String(localized: "Transaction saved")) {
                    EmptyView()
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showSavedToast)
        .navigationTitle(viewModel.editingItem == nil ? "New Transaction" : "Edit Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // No other dismissal affordance exists on this sheet besides swipe-down — give it an
            // explicit, discoverable exit (Nielsen: user control and freedom).
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            // Lives in the nav bar (not a pinned button above the keyboard) so it's never in a
            // fight with the keyboard's own accessory bar for screen space — same pattern as
            // Notes/Reminders. Used to be landscape-only; the portrait pinned-bar alternative was
            // tried and rejected (kept getting covered by, or visually clashing with, the
            // keyboard toolbar), so this is now unconditional.
            // Add mode only — scanning a receipt into an existing transaction's already-populated
            // form has murkier overwrite semantics, so it's out of scope for v1. Hidden for
            // Transfer too: a receipt is never a transfer between the user's own goals.
            if viewModel.editingItem == nil && viewModel.transactionType != .transfer {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openReceiptSourceDialog()
                    } label: {
                        // `camera.viewfinder` is a wide, asymmetric glyph that reads as squeezed
                        // inside a lone .topBarTrailing item's glass capsule — every other icon-only
                        // nav button in the app (eye, checkmark, trash) is roughly square. This is
                        // the same symbol Notes/Files use for their own document-scan button.
                        Image(systemName: "doc.text.viewfinder")
                    }
                    .accessibilityLabel("Scan receipt")
                    .accessibilityHint("Fill this transaction from a photo of a receipt")
                    // A real nav-bar button, unlike the keyboard-bar controls in
                    // TransactionFormTips.swift — .popoverTip() anchors from it directly, no
                    // pinned-card workaround needed.
                    .popoverTip(ScanReceiptTip())
                    .tipViewStyle(AppTipViewStyle())
                    .confirmationDialog(
                        "Scan Receipt",
                        isPresented: $showingReceiptSourceDialog,
                        titleVisibility: .visible
                    ) {
                        // Camera access is checked before presenting the scanner, not left to
                        // fail inside it — VNDocumentCameraViewController doesn't surface a denied
                        // permission as anything a user could act on (an AVFoundationErrorDomain
                        // -11852 alert, e.g.), it just fails to show a live feed.
                        Button("Take Photo") { requestCameraAccessThenScan() }
                        // No permission needed: PhotosPicker runs out-of-process.
                        Button("Choose Photo") { showingPhotoPicker = true }
                        Button("Cancel", role: .cancel) {}
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
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveTransaction()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(viewModel.editingItem == nil ? "Add Transaction" : "Update Transaction")
                // Edit mode: nothing to save until the user changes something. Add mode is
                // unaffected — isFormValid alone already gates it there.
                .disabled(!viewModel.isFormValid || (viewModel.editingItem != nil && !viewModel.hasChanges))
            }
            if viewModel.editingItem != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        requestDeleteTransaction()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    // A non-recurring transaction used to be removed immediately from the
                    // toolbar, beside Save. Keep deletion one deliberate step away from the
                    // primary edit action; recurring transactions present their scope chooser
                    // instead.
                    .confirmationDialog(
                        "Delete this transaction?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            deleteTransaction()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                    .confirmationDialog(
                        "This is part of a recurring series",
                        isPresented: Binding(
                            get: { pendingRecurrenceAction != nil },
                            set: { if !$0 { pendingRecurrenceAction = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button("This transaction", role: .destructive) { applyPendingAction(scope: .thisOnly) }
                        Button("This and future", role: .destructive) { applyPendingAction(scope: .thisAndFuture) }
                        Button("Cancel", role: .cancel) { pendingRecurrenceAction = nil }
                    }
                }
            }
        }
        .onAppear {
            viewModel.setTransactionViewModel()
            updateScanTipEligibility()
            if let scan = pendingInitialScan {
                pendingInitialScan = nil
                Task {
                    let learnedMerchants = (try? await viewModel.repo.fetchMerchantCategoryMappings()) ?? [:]
                    await viewModel.applyReceiptScan(scan, learnedMerchants: learnedMerchants)
                }
            }
        }
        .onChange(of: viewModel.transactionType) { _, _ in updateScanTipEligibility() }
        // Full-screen, not a sheet: VisionKit's own scanner UI is designed edge-to-edge like the
        // system Camera app — a sheet's rounded corners/grabber would fight its chrome.
        .fullScreenCover(isPresented: $showingDocumentScanner) {
            ReceiptDocumentScanner { result in
                showingDocumentScanner = false
                switch result {
                case .success(let images):
                    guard !images.isEmpty else { return } // user cancelled — leave the form alone
                    processReceiptImages(images)
                case .failure:
                    // Not `error.localizedDescription`: VisionKit's own capture failure is a raw
                    // AVFoundationErrorDomain code (e.g. -11800, "Unable to capture media" — the
                    // simulator has no camera at all) that means nothing to a user reading it.
                    receiptScanErrorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoPickerItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    receiptScanErrorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
                    return
                }
                processReceiptImages([image])
            }
        }
        .overlay {
            if isProcessingReceiptScan {
                ProgressView("Reading receipt…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert(
            "Couldn't read this receipt",
            isPresented: Binding(
                get: { receiptScanErrorMessage != nil },
                set: { if !$0 { receiptScanErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(receiptScanErrorMessage ?? "")
        }
    }

    /// Mirrors the scan button's own visibility guard so `ScanReceiptTip` never targets a control
    /// that isn't on screen (opening the sheet in edit mode, or switching to Transfer).
    private func updateScanTipEligibility() {
        ScanReceiptTip.isEligible = viewModel.editingItem == nil && viewModel.transactionType != .transfer
    }

    /// This sheet's own in-form "Scan receipt" toolbar button. The shell-level shortcut next to
    /// "+ Add" has its own separate flow (ReceiptScanShortcut) — it never calls this, since it
    /// runs capture before this sheet even opens.
    private func openReceiptSourceDialog() {
        // Amount auto-focuses on sheet open, and CurrencyAmountField only syncs its visible
        // text from `amount` while unfocused — so if the keyboard is still up when a scan
        // lands, the amount updates internally but never renders. Drop focus now.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        ScanReceiptTip().invalidate(reason: .actionPerformed)
        showingReceiptSourceDialog = true
    }

    /// Checks camera access before presenting `VNDocumentCameraViewController` rather than after:
    /// a denied permission doesn't stop that controller from being presented, it just fails to show
    /// a live feed and surfaces as an opaque `AVFoundationErrorDomain -11852` alert once capture is
    /// attempted — not something a user could act on.
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

    /// Runs Vision recognition + parsing off the main actor, then applies the result on it — the
    /// form's own values are never touched while `isProcessingReceiptScan` is true.
    private func processReceiptImages(_ images: [UIImage]) {
        isProcessingReceiptScan = true
        Task {
            defer { isProcessingReceiptScan = false }
            do {
                let document = try await ReceiptTextRecognizer.recognize(in: images)
                guard !document.lines.isEmpty else {
                    receiptScanErrorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
                    return
                }
                let scan = ReceiptParser.parse(document)
                let learnedMerchants = (try? await viewModel.repo.fetchMerchantCategoryMappings()) ?? [:]
                await viewModel.applyReceiptScan(scan, learnedMerchants: learnedMerchants)
            } catch {
                // Same reasoning as the capture-failure case above: a raw Vision/AVFoundation
                // error isn't something a user reading an alert can act on.
                receiptScanErrorMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
            }
        }
    }

    private func saveTransaction() {
        guard let existing = viewModel.editingItem else {
            Task {
                do {
                    if viewModel.isRecurring {
                        try await viewModel.saveRecurringTransaction()
                    } else {
                        // Guard nil (don't `else if`): a nil input must not fall through
                        // to the success path and show a false "saved". isFormValid gates
                        // the button, so this is defensive but explicit.
                        guard let input = viewModel.buildInput() else { return }
                        try await viewModel.repo.add(input)
                    }
                    dataChanged.bump()
                    // Must run before resetForm() clears receiptMerchant, and regardless of
                    // whether the user accepted the guessed category or corrected it — the
                    // correction is exactly what the learned tier needs.
                    await viewModel.recordReceiptLearningIfNeeded()
                    if viewModel.addAnother {
                        viewModel.resetForm()
                        savedCount += 1     // fires .sensoryFeedback(.success)
                        refocusToken += 1   // clears + re-focuses Amount (Task 2)
                        flashSavedToast()
                    } else {
                        dismiss()
                    }
                } catch {
                    // Keep the filled form; surface the existing error alert. No toast/haptic.
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showingErrorAlert = true
                }
            }
            return
        }
        guard let input = viewModel.buildInput() else { return }
        if existing.recurrenceRuleId != nil {
            pendingRecurrenceAction = .save(input)
        } else {
            Task {
                try? await viewModel.repo.update(id: existing.id, with: input)
                dataChanged.bump()
                dismiss()
            }
        }
    }

    private func deleteTransaction() {
        guard let existing = viewModel.editingItem else { return }
        if existing.recurrenceRuleId != nil {
            pendingRecurrenceAction = .delete
        } else {
            Task {
                try? await viewModel.repo.delete(id: existing.id)
                dataChanged.bump()
                dismiss()
            }
        }
    }

    private func requestDeleteTransaction() {
        guard let existing = viewModel.editingItem else { return }
        if existing.recurrenceRuleId != nil {
            deleteTransaction()
        } else {
            showingDeleteConfirmation = true
        }
    }

    private func applyPendingAction(scope: RecurrenceEditScope) {
        guard let action = pendingRecurrenceAction,
              let existing = viewModel.editingItem,
              let ruleId = existing.recurrenceRuleId else {
            pendingRecurrenceAction = nil
            return
        }
        pendingRecurrenceAction = nil
        Task {
            switch (action, scope) {
            case (.save(let input), .thisOnly):
                try? await viewModel.repo.update(id: existing.id, with: input)

            case (.save, .thisAndFuture):
                if let rule = try? await viewModel.repo.fetchRecurrenceRule(id: ruleId),
                   let ruleInput = viewModel.buildRecurrenceRuleInput(preserving: rule) {
                    try? await viewModel.repo.updateRecurrenceRule(id: ruleId, with: ruleInput)
                    try? await viewModel.repo.deleteOccurrences(recurrenceRuleId: ruleId, from: existing.timestamp)
                    // deleteOccurrences just removed the row being edited (its timestamp >= cutoff) along
                    // with any later ones. Re-materialize immediately — dismissing this sheet is neither a
                    // launch nor a foreground transition, so without this call the edited transaction would
                    // stay missing from Activity until the user backgrounds/relaunches the app.
                    try? await materializationService.materialize(using: viewModel.repo)
                }

            case (.delete, .thisOnly):
                try? await viewModel.repo.delete(id: existing.id)

            case (.delete, .thisAndFuture):
                let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: existing.timestamp) ?? existing.timestamp
                try? await viewModel.repo.closeRecurrenceRule(id: ruleId, endDate: dayBefore)
                try? await viewModel.repo.deleteOccurrences(recurrenceRuleId: ruleId, from: existing.timestamp)
            }
            dataChanged.bump()
            dismiss()
        }
    }

    private func flashSavedToast() {
        toastTask?.cancel()
        showSavedToast = true
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { showSavedToast = false }
        }
    }
}
