import SwiftUI

struct TransactionsShareRequest: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
}

/// Presents the system share controller from the currently visible UIKit
/// controller. Embedding `UIActivityViewController` inside a SwiftUI `.sheet`
/// makes SwiftUI own the detents and expands it to the large sheet height.
struct TransactionsSharePresenter: UIViewControllerRepresentable {
    @Binding var request: TransactionsShareRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        guard let request, context.coordinator.lastPresentedID != request.id else { return }
        context.coordinator.lastPresentedID = request.id
        let requestBinding = $request

        Task { @MainActor [weak anchor] in
            // Let SwiftUI finish committing the state update before resolving the
            // currently visible controller from the active window hierarchy.
            await Task.yield()
            guard
                let anchor,
                let root = anchor.view.window?.rootViewController,
                let presenter = visibleViewController(from: root)
            else { return }

            let activityController = UIActivityViewController(
                activityItems: [request.fileURL],
                applicationActivities: nil
            )

            // UIActivityViewController is a popover on regular-width devices and
            // requires an anchor. This representable fills the export row's
            // background, so its bounds preserve the visual relationship to the
            // action. On iPhone the system ignores the anchor and uses its native
            // compact bottom-sheet presentation.
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = anchor.view
                popover.sourceRect = anchor.view.bounds
            }

            presenter.present(activityController, animated: true) {
                // The activity controller retains its items. Clearing the request
                // prevents an unrelated SwiftUI reconstruction from presenting it again.
                requestBinding.wrappedValue = nil
            }
        }
    }

    @MainActor
    private func visibleViewController(from root: UIViewController?) -> UIViewController? {
        guard let root else { return nil }

        if let presented = root.presentedViewController, !presented.isBeingDismissed {
            return visibleViewController(from: presented)
        }
        if let navigationController = root as? UINavigationController {
            return visibleViewController(from: navigationController.visibleViewController)
        }
        if let tabController = root as? UITabBarController {
            return visibleViewController(from: tabController.selectedViewController)
        }

        return root
    }

    final class Coordinator {
        var lastPresentedID: UUID?
    }
}
