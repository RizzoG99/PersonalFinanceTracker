//
//  SafeToSpendSnapshotUpdater.swift
//  PersonalFinanceTraker
//

import Foundation
import WidgetKit

enum SafeToSpendSnapshotUpdater {
    static func refresh(
        transactions: [TransactionSnapshot],
        activeRules: [RecurrenceRuleSnapshot],
        payCycleStartDay: Int,
        bufferPercent: Int,
        currencyService: CurrencyService = CurrencyService()
    ) {
        let measurement = PerformanceAuditRecorder.begin("SafeToSpend.snapshot.write")
        var outcome: PerformanceAuditRecorder.Outcome = .completed
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: transactions,
            activeRules: activeRules,
            payCycleStartDay: payCycleStartDay,
            bufferPercent: bufferPercent,
            currencyService: currencyService
        )
        do {
            try snapshot.write()
        } catch {
            // The widget keeps showing the previous snapshot — at least leave a trace why.
            print("Safe to Spend snapshot write failed: \(error)")
            outcome = .failed
        }
        PerformanceAuditRecorder.event("WidgetKit.reload.request", metadata: "kind=SafeToSpendWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: SafeToSpendWidgetKind.name)
        PerformanceAuditRecorder.end(
            measurement,
            outcome: outcome,
            metadata: "transactions=\(transactions.count) rules=\(activeRules.count)"
        )
    }
}
