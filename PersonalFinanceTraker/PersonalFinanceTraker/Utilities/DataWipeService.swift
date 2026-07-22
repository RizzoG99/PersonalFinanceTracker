import SwiftData

enum DataWipeService {
    static func wipeAllData(context: ModelContext) throws {
        try context.delete(model: TransactionModel.self)
        try context.delete(model: CategoryModel.self)
        try context.delete(model: CreditCardModel.self)
        try context.delete(model: GoalModel.self)
        try context.delete(model: HealthScoreSnapshot.self)
        try context.delete(model: DailyForecastCache.self)
        try context.save()
    }
}
