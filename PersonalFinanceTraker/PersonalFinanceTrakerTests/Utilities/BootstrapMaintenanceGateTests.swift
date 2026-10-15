import Testing
@testable import PersonalFinanceTraker

private actor CompletionFlag {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    var isCompleted: Bool { completed }
}

struct BootstrapMaintenanceGateTests {
    @Test func defersMaintenanceUntilInteractiveBootstrapFinishes() async {
        let gate = BootstrapMaintenanceGate()
        let completion = CompletionFlag()
        let task = Task {
            await gate.waitUntilInteractiveBootstrapCompletes()
            await completion.markCompleted()
        }

        for _ in 0..<100 {
            if await gate.waitingCount > 0 { break }
            await Task.yield()
        }

        let waitingCount = await gate.waitingCount
        let completedBeforeOpening = await completion.isCompleted
        #expect(waitingCount == 1)
        #expect(!completedBeforeOpening)

        await gate.finishInteractiveBootstrap()
        await task.value

        let completedAfterOpening = await completion.isCompleted
        #expect(completedAfterOpening)
    }

    @Test func doesNotDelayMaintenanceAfterBootstrapHasFinished() async {
        let gate = BootstrapMaintenanceGate()
        await gate.finishInteractiveBootstrap()
        await gate.waitUntilInteractiveBootstrapCompletes()

        let waitingCount = await gate.waitingCount
        #expect(waitingCount == 0)
    }
}
