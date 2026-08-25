import SwiftData

enum DataWipeService {
    static func wipeAllData(context: ModelContext) throws {
        try context.delete(model: TransactionModel.self)
        // Rules outlived the wipe before this line existed: RecurrenceMaterializationService then
        // re-created transactions from them at the next launch, and import stopped offering any
        // recurrence suggestion because every candidate still matched a surviving rule.
        try context.delete(model: RecurrenceRule.self)
        try context.delete(model: CategoryModel.self)
        try context.delete(model: CreditCardModel.self)
        try context.delete(model: GoalModel.self)
        try context.delete(model: HealthScoreSnapshot.self)
        try context.delete(model: DailyForecastCache.self)
        try context.save()
    }
}
