import Foundation

/// Holds non-interactive launch work until the shell has loaded the data needed for its first
/// user interaction. This prevents a daily backup from competing with the initial tab switch.
actor BootstrapMaintenanceGate {
    private var isOpen = false
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    var waitingCount: Int { waitingContinuations.count }

    func waitUntilInteractiveBootstrapCompletes() async {
        guard !isOpen else { return }

        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func finishInteractiveBootstrap() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = waitingContinuations
        waitingContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}
