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
        try? snapshot.write()
        WidgetCenter.shared.reloadTimelines(ofKind: SafeToSpendWidgetKind.name)
    }
}
