import Foundation

struct ScoreComponent: Identifiable {
    let id = UUID()
    let name: String
    let score: Int
    let max: Int
    let explanation: String
    let tip: String?
}
