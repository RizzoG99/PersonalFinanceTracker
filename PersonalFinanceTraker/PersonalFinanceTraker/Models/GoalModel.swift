//
//  GoalModel.swift
//  PersonalFinanceTraker
//

import SwiftData
import Foundation
import SwiftUI

@Model
final class GoalModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var targetAmount: Decimal
    var deadline: Date?
    var colorToken: String
    var iconName: String
    var createdAt: Date

    var goalColor: Color { Color(colorToken) }

    init(
        name: String,
        targetAmount: Decimal,
        deadline: Date? = nil,
        colorToken: String = "categoryIndigo",
        iconName: String = "star.fill"
    ) {
        self.id = UUID()
        self.name = name
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.colorToken = colorToken
        self.iconName = iconName
        self.createdAt = Date()
    }
}

extension GoalModel: Hashable {
    static func == (lhs: GoalModel, rhs: GoalModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum GoalIcon: String, CaseIterable {
    case emergency = "cross.circle.fill"
    case vacation  = "airplane"
    case house     = "house.fill"
    case gift      = "gift.fill"
    case courses   = "graduationcap.fill"
    case other     = "star.fill"

    var label: String {
        switch self {
        case .emergency: return "Emergency"
        case .vacation:  return "Vacation"
        case .house:     return "House"
        case .gift:      return "Gift"
        case .courses:   return "Courses"
        case .other:     return "Other"
        }
    }
}
