import Testing
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct PerformanceAuditRecorderTests {
    @Test func disabledRecorderDoesNotAccumulateEvents() {
        PerformanceAuditRecorder.resetForTesting(isEnabled: false)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: false) }

        PerformanceAuditRecorder.event("Recorder.disabled")

        #expect(PerformanceAuditRecorder.testingSnapshot().counters.isEmpty)
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
