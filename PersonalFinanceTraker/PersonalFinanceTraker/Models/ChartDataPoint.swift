//
//  ChartDataPoint.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation

public struct ChartDataPoint {
    public let period: String
    /// Representative date for this period, used as continuous X axis value
    public let date: Date
    public let income: Decimal
    /// Stored as positive value
    public let expenses: Decimal
    public let netAmount: Decimal

    public init(period: String, income: Decimal, expenses: Decimal, date: Date = Date()) {
        self.period = period
        self.date = date
        self.income = income
        self.expenses = expenses
        self.netAmount = income - expenses
    }

    public var hasActivity: Bool { income > 0 || expenses > 0 }
    public var isProfit: Bool    { netAmount > 0 }
    public var isLoss: Bool      { netAmount < 0 }
    public var isBreakEven: Bool { netAmount == 0 }
}
