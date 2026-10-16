import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct PerformanceAuditRecorderTests {
    @Test @MainActor func synchronousMeasurementPreservesResultsAndMeasuresExecutingThread() {
        PerformanceAuditRecorder.resetForTesting(isEnabled: true)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: false) }
        let result = PerformanceAuditRecorder.measure("Recorder.sync") {
            (1...10_000).reduce(Decimal.zero) { $0 + Decimal($1) }
        }
        #expect(result == 50_005_000)
        let samples = PerformanceAuditRecorder.testingSnapshot().synchronousSamples
        #expect(samples.count == 1)
        #expect(samples.first?.isMainThread == true)
        #expect((samples.first?.wallNanoseconds ?? 0) > 0)
        #expect((samples.first?.threadCPUNanoseconds ?? 0) > 0)
    }

    @Test func disabledRecorderDoesNotAccumulateEvents() {
        PerformanceAuditRecorder.resetForTesting(isEnabled: false)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: false) }

        PerformanceAuditRecorder.event("Recorder.disabled")
        #expect(PerformanceAuditRecorder.measure("Recorder.disabled") { 42 } == 42)

        #expect(PerformanceAuditRecorder.testingSnapshot().counters.isEmpty)
        #expect(PerformanceAuditRecorder.testingSnapshot().synchronousSamples.isEmpty)
    }

    @Test func synchronousMeasurementPreservesThrownError() {
        enum ExpectedError: Error { case expected }
        PerformanceAuditRecorder.resetForTesting(isEnabled: true)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: false) }
        #expect(throws: ExpectedError.self) {
            try PerformanceAuditRecorder.measure("Recorder.failure") { throw ExpectedError.expected }
        }
        let snapshot = PerformanceAuditRecorder.testingSnapshot()
        #expect(snapshot.counters["Recorder.failure.failed"] == 1)
        #expect(snapshot.activeIntervals["Recorder.failure"] == 0)
        #expect(snapshot.synchronousSamples.count == 1)
    }

    @Test func recordsCountsDurationCommitAndMaximumConcurrency() {
        PerformanceAuditRecorder.resetForTesting(isEnabled: true)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: false) }

        let first = PerformanceAuditRecorder.begin("Recorder.load")
        let second = PerformanceAuditRecorder.begin("Recorder.load")
        PerformanceAuditRecorder.commit(second)
        PerformanceAuditRecorder.end(second, outcome: .completed)
        PerformanceAuditRecorder.end(first, outcome: .cancelled)

        let snapshot = PerformanceAuditRecorder.testingSnapshot()
        #expect(snapshot.counters["Recorder.load.start"] == 2)
        #expect(snapshot.counters["Recorder.load.commit"] == 1)
        #expect(snapshot.counters["Recorder.load.completed"] == 1)
        #expect(snapshot.counters["Recorder.load.cancelled"] == 1)
        #expect(snapshot.activeIntervals["Recorder.load"] == 0)
        #expect(snapshot.maximumConcurrentIntervals["Recorder.load"] == 2)
        #expect((snapshot.totalDurationNanoseconds["Recorder.load"] ?? 0) > 0)
    }
}
