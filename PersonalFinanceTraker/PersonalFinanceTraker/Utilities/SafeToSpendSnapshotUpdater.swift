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
        }
        WidgetCenter.shared.reloadTimelines(ofKind: SafeToSpendWidgetKind.name)
    }
}
