import Foundation

/// Polls `condition` until it holds or `timeout` elapses. Returns whether it held.
///
/// Use this instead of `try await Task.sleep(...)` when waiting for an async
/// side effect. A fixed sleep is racy by construction: it has to be long enough
/// for the slowest run on the busiest machine, and every passing run still pays
/// the full cost. Two suites in this project failed intermittently for exactly
/// that reason — the sleep was tuned on an idle machine and came up short when
/// the whole suite ran at once.
///
/// Polling inverts both properties: it returns as soon as the condition holds,
/// and only spends the whole timeout when something is genuinely wrong. Set the
/// timeout generously — it is a failure deadline, not an expected wait.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Waits for a value to become non-nil, returning it.
@MainActor
func waitForValue<T>(
    timeout: Duration = .seconds(5),
    _ produce: () -> T?
) async -> T? {
    _ = await waitUntil(timeout: timeout) { produce() != nil }
    return produce()
}
