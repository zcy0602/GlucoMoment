//
//  PersistenceRepositoryTests.swift
//  GlucoMomentTests
//

import Foundation
import SwiftData
import Testing
@testable import GlucoMoment

@Suite("SwiftData 持久化仓库", .serialized)
struct PersistenceRepositoryTests {
    @MainActor
    static let container: ModelContainer = {
        do {
            return try ModelContainerFactory.makeInMemory()
        } catch {
            preconditionFailure("无法创建测试数据库：\(error.localizedDescription)")
        }
    }()

    @MainActor
    static func resetStore() throws {
        let context = container.mainContext
        for entity in try context.fetch(FetchDescriptor<MealRecordEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<MealFoodItemEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<MealAnalysisSnapshotEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<GlucoseSampleEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<HealthKitSyncStateEntity>()) {
            context.delete(entity)
        }
        try context.save()
    }
}
