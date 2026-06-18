import SwiftData
import Foundation

@Model
final class HealthScoreSnapshot {
    var timestamp: Date
    var score: Int
    var savingsScore: Int
    var stabilityScore: Int
    var adherenceScore: Int
    var subscriptionScore: Int

    init(timestamp: Date, score: Int, savingsScore: Int, stabilityScore: Int,
         adherenceScore: Int, subscriptionScore: Int) {
        self.timestamp = timestamp
        self.score = score
        self.savingsScore = savingsScore
        self.stabilityScore = stabilityScore
        self.adherenceScore = adherenceScore
        self.subscriptionScore = subscriptionScore
    }
}
