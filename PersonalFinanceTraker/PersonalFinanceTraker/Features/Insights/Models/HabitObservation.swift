import Foundation

struct HabitObservation: Identifiable {
    let id = UUID()
    let sfSymbol: String
    let title: String
    let detail: String
}
