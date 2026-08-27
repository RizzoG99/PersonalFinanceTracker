//
//  ReceiptDocumentScanner.swift
//  PersonalFinanceTraker
//
//  VNDocumentCameraViewController wrapped for SwiftUI — native edge detection and cropping, no
//  third-party camera code. See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import SwiftUI
import VisionKit

struct ReceiptDocumentScanner: UIViewControllerRepresentable {
    var onFinish: (Result<[UIImage], Error>) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Result<[UIImage], Error>) -> Void

        init(onFinish: @escaping (Result<[UIImage], Error>) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(.success(images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(.success([])) // Cancel is a no-op, not a failure — caller treats empty as "nothing to do".
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(.failure(error))
        }
    }
}
