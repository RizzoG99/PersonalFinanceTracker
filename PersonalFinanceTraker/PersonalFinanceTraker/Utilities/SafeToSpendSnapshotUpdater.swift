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
        currencyService: CurrencyService = CurrencyService()
    ) {
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: transactions,
            activeRules: activeRules,
            payCycleStartDay: payCycleStartDay,
            currencyService: currencyService
        )
        try? snapshot.write()
        WidgetCenter.shared.reloadTimelines(ofKind: SafeToSpendWidgetKind.name)
    }
}
