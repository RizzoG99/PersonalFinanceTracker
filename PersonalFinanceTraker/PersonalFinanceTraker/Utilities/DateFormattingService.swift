import Foundation
import SwiftUI

extension Date {
    func formattedForTransaction() -> String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return self.formatted(date: .abbreviated, time: .omitted)
    }

    func formattedForChartAxis(period: TimePeriod) -> String {
        switch period {
        case .week:  return self.formatted(.dateTime.weekday(.abbreviated))
        case .month: return self.formatted(.dateTime.month(.abbreviated).day())
        case .year:  return self.formatted(.dateTime.month(.abbreviated))
        }
    }
}
