import Testing
import Foundation
@testable import PersonalFinanceTraker

struct TimelineAnomalyServiceTests {

    private func point(_ period: String, expenses: Decimal) -> ChartDataPoint {
        ChartDataPoint(period: period, income: 0, expenses: expenses)
    }

    @Test func emptyInputReturnsEmpty() {
        #expect(TimelineAnomalyService().annotateWithSpikes([]).isEmpty)
    }

    @Test func uniformValuesProduceNoSpikes() {
        let input = (1...5).map { point("W\($0)", expenses: 100) }
        let result = TimelineAnomalyService().annotateWithSpikes(input)
        #expect(result.allSatisfy { !$0.isSpike })
    }

    @Test func singleOutlierIsMarkedSpike() {
        let input = [
            point("Jan", expenses: 100),
            point("Feb", expenses: 100),
            point("Mar", expenses: 100),
            point("Apr", expenses: 800),   // well above mean + 1.5σ
        ]
        let result = TimelineAnomalyService().annotateWithSpikes(input)
        #expect(result.last?.isSpike == true)
        #expect(result.dropLast().allSatisfy { !$0.isSpike })
    }

    @Test func fewerThanThreeNonZeroWeeksNeverSpike() {
        // Only 2 nonzero weeks — not enough baseline, even though 1000 alone
        // would clear mean + 1.5σ against these values.
        let input = [
            point("Jan", expenses: 0),
            point("Feb", expenses: 200),
            point("Mar", expenses: 1000),
        ]
        let result = TimelineAnomalyService().annotateWithSpikes(input)
        #expect(result.allSatisfy { !$0.isSpike })
    }

    @Test func zeroExpensesAreNeverSpikes() {
        let input = [
            point("Jan", expenses: 0),
            point("Feb", expenses: 0),
            point("Mar", expenses: 0),
        ]
        let result = TimelineAnomalyService().annotateWithSpikes(input)
        #expect(result.allSatisfy { !$0.isSpike })
    }

    @Test func periodLabelsPreservedAfterAnnotation() {
        let input = [point("Alpha", expenses: 10), point("Beta", expenses: 20)]
        let result = TimelineAnomalyService().annotateWithSpikes(input)
        #expect(result.map { $0.period } == ["Alpha", "Beta"])
    }
}
