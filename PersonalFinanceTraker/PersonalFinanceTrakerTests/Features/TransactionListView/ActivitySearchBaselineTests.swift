import Foundation
import Testing
@testable import PersonalFinanceTraker

extension PerformanceRecorderSerialTests {
/// Explicitly selected diagnostic baseline, not a device responsiveness or frame benchmark.
/// Run this suite alone: the opt-in recorder's counters are process-wide. No latency budget
/// is asserted until a target-device budget and baseline variance have been established.
@Suite(.serialized)
struct ActivitySearchBaselineTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_SEARCH_BASELINE"] == "1"))
    @MainActor func fiveThousandTransactions() async throws {
        let wasEnabled = PerformanceAuditRecorder.isEnabled
        PerformanceAuditRecorder.resetForTesting(isEnabled: true)
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: wasEnabled) }

        let repo = MockTransactionRepository()
        let anchor = Date(timeIntervalSince1970: 1_791_547_200)
        repo.stubbedTransactions = (0..<5_000).map { index in
            .test(
                timestamp: anchor.addingTimeInterval(-Double(index % 365) * 86_400),
                amount: -Decimal(index + 1),
                note: index.isMultiple(of: 2) ? "Coffee \(index)" : "Groceries \(index)",
                category: index.isMultiple(of: 2) ? "Food" : "Household"
            )
        }
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        await vm.groupingTask?.value
        #expect(vm.transactions.count == 5_000)

        let queries: [(label: String, text: String, count: Int)] = [
            ("broad", "Coffee", 2_500),
            ("extend", "Coffee 4242", 1),
            ("miss", "zzqnomatch", 0),
            ("clear", "", 5_000),
        ]
        let names = ["Activity.filter", "Activity.derivedFilters", "Activity.group",
                     "Activity.group.publish", "Activity.page.prepare"]
        let clock = ContinuousClock()
        // Round zero exposes first-use cost; rounds 1...5 are the warm distribution.
        for round in 0...5 {
            for query in queries {
                let before = PerformanceAuditRecorder.testingSnapshot()
                let start = clock.now
                vm.searchText = query.text
                await vm.searchDebounceTask?.value
                let filterReturned = start.duration(to: clock.now)
                await vm.groupingTask?.value
                let grouped = start.duration(to: clock.now)
                let page = vm.activityPage
                let after = PerformanceAuditRecorder.testingSnapshot()

                #expect(vm.filteredItems.count == query.count)
                let rows = vm.groupedItems.flatMap(\.1).compactMap(\.transaction)
                #expect(Set(rows.map(\.id)) == Set(vm.filteredItems.map(\.id)))
                #expect(rows.count == query.count)
                #expect(page.groups.flatMap(\.1).count == min(query.count, 200))
                #expect(page.remainingRowCount == max(0, query.count - 200))

                var record: [String: Any] = [
                    "round": round, "query": query.label, "input_count": 5_000,
                    "result_count": query.count, "intended_debounce_ms": 250,
                    "query_to_filter_return_ms": milliseconds(filterReturned),
                    "query_to_group_return_ms": milliseconds(grouped),
                ]
                for name in names {
                    let count = (after.counters["\(name).start"] ?? 0)
                        - (before.counters["\(name).start"] ?? 0)
                    let elapsed = (after.totalDurationNanoseconds[name] ?? 0)
                        - (before.totalDurationNanoseconds[name] ?? 0)
                    // Reject a sample contaminated by another Activity instance in the host.
                    #expect(count == (name == "Activity.filter" && query.text.isEmpty ? 0 : 1))
                    #expect((after.activeIntervals[name] ?? 0) == 0)
                    record["\(name).count"] = count
                    record["\(name).elapsed_ms"] = Double(elapsed) / 1_000_000
                }
                let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                print("PFT_SEARCH_BASELINE \(String(decoding: json, as: UTF8.self))")
            }
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
}
