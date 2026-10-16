//
//  PerformanceAuditRecorder.swift
//  PersonalFinanceTraker
//

import Dispatch
import Darwin
import Foundation
import OSLog

/// Opt-in instrumentation used to validate `.performance-audit` findings.
///
/// Nothing is recorded unless the process is launched with `-performanceAudit`
/// or `PFT_PERFORMANCE_AUDIT=1`. The fixed `PFT_PERF` prefix keeps collection
/// scripts independent from unrelated unified-log traffic.
enum PerformanceAuditRecorder {
    enum Outcome: String, Sendable {
        case completed
        case cancelled
        case failed
    }

    struct Snapshot: Equatable, Sendable {
        let counters: [String: Int]
        let activeIntervals: [String: Int]
        let maximumConcurrentIntervals: [String: Int]
        let totalDurationNanoseconds: [String: UInt64]
        let synchronousSamples: [SynchronousSample]
    }

    /// Only synchronous scopes: thread CPU must never span an actor hop or suspension.
    struct SynchronousSample: Equatable, Sendable, Codable {
        let name: String
        let wallNanoseconds: UInt64
        let threadCPUNanoseconds: UInt64
        let isMainThread: Bool
    }

    struct Interval: @unchecked Sendable {
        fileprivate let name: StaticString
        fileprivate let key: String
        fileprivate let signpostID: OSSignpostID
        fileprivate let sequence: Int
        fileprivate let startedAt: UInt64
    }

    private struct State {
        var isEnabled: Bool
        var nextSequence = 0
        var counters: [String: Int] = [:]
        var activeIntervals: [String: Int] = [:]
        var maximumConcurrentIntervals: [String: Int] = [:]
        var totalDurationNanoseconds: [String: UInt64] = [:]
        var synchronousSamples: [SynchronousSample] = []
    }

    private final class LockedStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var state: State

        init(isEnabled: Bool) {
            state = State(isEnabled: isEnabled)
        }

        func enabled() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return state.isEnabled
        }

        func recordEvent(_ key: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            state.counters[key, default: 0] += 1
            return state.counters[key, default: 0]
        }

        func begin(_ key: String) -> (sequence: Int, count: Int, active: Int) {
            lock.lock()
            defer { lock.unlock() }
            state.nextSequence += 1
            state.counters["\(key).start", default: 0] += 1
            state.activeIntervals[key, default: 0] += 1
            let active = state.activeIntervals[key, default: 0]
            state.maximumConcurrentIntervals[key] = max(
                state.maximumConcurrentIntervals[key, default: 0],
                active
            )
            return (state.nextSequence, state.counters["\(key).start", default: 0], active)
        }

        func end(_ key: String, outcome: Outcome, duration: UInt64) -> (count: Int, active: Int) {
            lock.lock()
            defer { lock.unlock() }
            let outcomeKey = "\(key).\(outcome.rawValue)"
            state.counters[outcomeKey, default: 0] += 1
            state.activeIntervals[key] = max(0, state.activeIntervals[key, default: 0] - 1)
            state.totalDurationNanoseconds[key, default: 0] += duration
            return (state.counters[outcomeKey, default: 0], state.activeIntervals[key, default: 0])
        }

        func snapshot() -> Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return Snapshot(
                counters: state.counters,
                activeIntervals: state.activeIntervals,
                maximumConcurrentIntervals: state.maximumConcurrentIntervals,
                totalDurationNanoseconds: state.totalDurationNanoseconds,
                synchronousSamples: state.synchronousSamples
            )
        }

        func record(_ sample: SynchronousSample) {
            lock.lock()
            defer { lock.unlock() }
            // Full samples are only needed by short harness runs. Longer device
            // sessions retain all signposts without growing this in-memory copy.
            if state.synchronousSamples.count < 4_096 {
                state.synchronousSamples.append(sample)
            }
        }

        func resetForTesting(isEnabled: Bool) {
            lock.lock()
            defer { lock.unlock() }
            state = State(isEnabled: isEnabled)
        }
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "PersonalFinanceTraker"
    private static let pointsOfInterest = OSLog(subsystem: subsystem, category: .pointsOfInterest)
    private static let logger = Logger(subsystem: subsystem, category: "PerformanceAudit")
    private static let scenario: String = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-performanceAuditScenario"),
              arguments.indices.contains(index + 1)
        else { return "unspecified" }
        return arguments[index + 1]
    }()
    private static let storage = LockedStorage(
        isEnabled: ProcessInfo.processInfo.arguments.contains("-performanceAudit")
            || ProcessInfo.processInfo.environment["PFT_PERFORMANCE_AUDIT"] == "1"
    )

    static var isEnabled: Bool { storage.enabled() }

    static func measure<T>(
        _ name: StaticString, metadata: @autoclosure () -> String = "",
        _ operation: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try operation() }
        let detail = metadata()
        let interval = begin(name, metadata: detail)
        let wall = DispatchTime.now().uptimeNanoseconds
        let cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        var outcome: Outcome = .completed
        defer {
            let cpuElapsed = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpu
            let elapsed = DispatchTime.now().uptimeNanoseconds - wall
            storage.record(SynchronousSample(
                name: String(describing: name), wallNanoseconds: elapsed,
                threadCPUNanoseconds: cpuElapsed, isMainThread: Thread.isMainThread
            ))
            end(interval, outcome: outcome, metadata: "\(detail) sync_wall_ns=\(elapsed) thread_cpu_ns=\(cpuElapsed)")
        }
        do {
            return try operation()
        } catch {
            outcome = .failed
            throw error
        }
    }

    static func event(_ name: StaticString, metadata: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let key = String(describing: name)
        let count = storage.recordEvent(key)
        let detail = metadata()
        os_signpost(
            .event,
            log: pointsOfInterest,
            name: name,
            "count=%{public}d main=%{public}d metadata=%{public}@",
            count,
            Thread.isMainThread ? 1 : 0,
            detail as NSString
        )
        logger.notice(
            "PFT_PERF kind=event scenario=\(scenario, privacy: .public) name=\(key, privacy: .public) count=\(count) main=\(Thread.isMainThread) metadata=\(detail, privacy: .public)"
        )
    }

    static func begin(_ name: StaticString, metadata: @autoclosure () -> String = "") -> Interval? {
        guard isEnabled else { return nil }
        let key = String(describing: name)
        let values = storage.begin(key)
        let detail = metadata()
        let signpostID = OSSignpostID(log: pointsOfInterest)
        os_signpost(
            .begin,
            log: pointsOfInterest,
            name: name,
            signpostID: signpostID,
            "sequence=%{public}d main=%{public}d metadata=%{public}@",
            values.sequence,
            Thread.isMainThread ? 1 : 0,
            detail as NSString
        )
        logger.notice(
            "PFT_PERF kind=begin scenario=\(scenario, privacy: .public) name=\(key, privacy: .public) sequence=\(values.sequence) count=\(values.count) active=\(values.active) main=\(Thread.isMainThread) metadata=\(detail, privacy: .public)"
        )
        return Interval(
            name: name,
            key: key,
            signpostID: signpostID,
            sequence: values.sequence,
            startedAt: DispatchTime.now().uptimeNanoseconds
        )
    }

    static func commit(_ interval: Interval?, metadata: @autoclosure () -> String = "") {
        guard let interval else { return }
        let key = "\(interval.key).commit"
        let count = storage.recordEvent(key)
        let detail = metadata()
        logger.notice(
            "PFT_PERF kind=commit scenario=\(scenario, privacy: .public) name=\(interval.key, privacy: .public) sequence=\(interval.sequence) count=\(count) metadata=\(detail, privacy: .public)"
        )
    }

    static func end(
        _ interval: Interval?,
        outcome: Outcome = .completed,
        metadata: @autoclosure () -> String = ""
    ) {
        guard let interval else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds - interval.startedAt
        let values = storage.end(interval.key, outcome: outcome, duration: elapsed)
        let detail = metadata()
        os_signpost(
            .end,
            log: pointsOfInterest,
            name: interval.name,
            signpostID: interval.signpostID,
            "sequence=%{public}d main=%{public}d outcome=%{public}@ metadata=%{public}@",
            interval.sequence,
            Thread.isMainThread ? 1 : 0,
            outcome.rawValue as NSString,
            detail as NSString
        )
        logger.notice(
            "PFT_PERF kind=end scenario=\(scenario, privacy: .public) name=\(interval.key, privacy: .public) sequence=\(interval.sequence) outcome=\(outcome.rawValue, privacy: .public) count=\(values.count) active=\(values.active) duration_ns=\(elapsed) main=\(Thread.isMainThread) metadata=\(detail, privacy: .public)"
        )
    }

    static func dump(reason: StaticString) {
        guard isEnabled else { return }
        let current = storage.snapshot()
        let reasonText = String(describing: reason)
        for (name, count) in current.counters.sorted(by: { $0.key < $1.key }) {
            logger.notice(
                "PFT_PERF kind=summary scenario=\(scenario, privacy: .public) reason=\(reasonText, privacy: .public) name=\(name, privacy: .public) count=\(count)"
            )
        }
        for (name, maximum) in current.maximumConcurrentIntervals.sorted(by: { $0.key < $1.key }) {
            logger.notice(
                "PFT_PERF kind=concurrency scenario=\(scenario, privacy: .public) reason=\(reasonText, privacy: .public) name=\(name, privacy: .public) maximum=\(maximum)"
            )
        }
    }

    static func testingSnapshot() -> Snapshot {
        storage.snapshot()
    }

    static func resetForTesting(isEnabled: Bool) {
        storage.resetForTesting(isEnabled: isEnabled)
    }
}
