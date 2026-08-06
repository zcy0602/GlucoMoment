//
//  HealthKitSynchronizedRepositoryTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@Suite("HealthKit 双向同步仓储")
@MainActor
struct HealthKitSynchronizedRepositoryTests {
    @Test("App 血糖保存会写入 HealthKit，删除会同时删除")
    func savesAndDeletesGlucoseInBothStores() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let local = SwiftDataGlucoseRepository(modelContainer: container)
        let states = HealthKitSyncStateRepository(modelContainer: container)
        let healthKit = StubHealthKitStoreClient()
        let repository = HealthKitSynchronizedGlucoseRepository(
            local: local,
            syncStates: states,
            healthKit: healthKit
        )
        let reading = GlucoseReading(measuredAt: .now, value: 6.4)

        try await repository.save(reading)

        #expect(healthKit.savedGlucoseIDs == [reading.id])
        #expect(try states.state(recordID: reading.id, kind: .glucose)?.status == .synced)
        #expect(try local.reading(id: reading.id) != nil)

        try await repository.delete(id: reading.id)

        #expect(healthKit.deletedGlucoseIDs == [reading.id])
        #expect(try local.reading(id: reading.id) == nil)
        #expect(try states.state(recordID: reading.id, kind: .glucose) == nil)
    }

    @Test("App 饮食保存与删除会同步 HealthKit")
    func savesAndDeletesMealInBothStores() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let states = HealthKitSyncStateRepository(modelContainer: container)
        let local = SwiftDataMealRepository(modelContainer: container, syncStates: states)
        let healthKit = StubHealthKitStoreClient()
        let repository = HealthKitSynchronizedMealRepository(
            local: local,
            syncStates: states,
            healthKit: healthKit
        )
        let meal = MealRecord(
            eatenAt: .now,
            mealPeriod: .lunch,
            title: "测试餐",
            source: .manual,
            caloriesKcal: 420,
            carbohydratesGrams: 48,
            proteinGrams: 25,
            fatGrams: 14,
            fiberGrams: 7,
            items: []
        )

        try await repository.save(meal)

        #expect(healthKit.savedMealIDs == [meal.id])
        #expect(try states.state(recordID: meal.id, kind: .meal)?.status == .synced)

        try await repository.delete(id: meal.id)

        #expect(healthKit.deletedMealIDs == [meal.id])
        #expect(try local.meal(id: meal.id) == nil)
    }

    @Test("从 HealthKit 导入饮食时保留未提供的营养项")
    func importsPartialNutritionAvailability() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let states = HealthKitSyncStateRepository(modelContainer: container)
        let local = SwiftDataMealRepository(modelContainer: container, syncStates: states)
        let healthKit = StubHealthKitStoreClient()
        let repository = HealthKitSynchronizedMealRepository(
            local: local,
            syncStates: states,
            healthKit: healthKit
        )
        let externalMeal = MealRecord(
            eatenAt: .now,
            mealPeriod: .dinner,
            title: "外部餐食",
            source: .healthKit,
            caloriesKcal: 0,
            carbohydratesGrams: 36,
            proteinGrams: 0,
            fatGrams: 0,
            fiberGrams: 0,
            items: [],
            nutritionAvailability: [.carbohydrates]
        )
        healthKit.externalMealImports = [
            HealthKitMealImport(
                meal: externalMeal,
                externalIdentifier: externalMeal.id.uuidString
            )
        ]

        _ = try await repository.synchronize()

        let storedMeal = try local.meal(id: externalMeal.id)
        let imported = try #require(storedMeal)
        #expect(imported.nutritionAvailability == [.carbohydrates])
        #expect(imported.carbohydratesGrams == 36)
        #expect(!imported.nutritionAvailability.contains(.energy))
    }
}

@MainActor
private final class StubHealthKitStoreClient: HealthKitStoreClientProtocol {
    let isHealthDataAvailable = true
    var savedGlucoseIDs: [UUID] = []
    var deletedGlucoseIDs: [UUID] = []
    var savedMealIDs: [UUID] = []
    var deletedMealIDs: [UUID] = []
    var externalMealImports: [HealthKitMealImport] = []

    func requestAuthorization() async throws {}

    func glucoseSnapshot() async throws -> HealthKitGlucoseSnapshot {
        HealthKitGlucoseSnapshot(
            externalReadings: [],
            ownedLocalRecordIDs: Set(savedGlucoseIDs)
        )
    }

    func mealSnapshot() async throws -> HealthKitMealSnapshot {
        HealthKitMealSnapshot(
            externalMeals: externalMealImports,
            ownedLocalRecordIDs: Set(savedMealIDs)
        )
    }

    func saveGlucose(_ reading: GlucoseReading) async throws -> String {
        savedGlucoseIDs.append(reading.id)
        return "health-glucose-\(reading.id.uuidString)"
    }

    func saveMeal(_ meal: MealRecord) async throws -> String {
        savedMealIDs.append(meal.id)
        return "health-meal-\(meal.id.uuidString)"
    }

    func deleteGlucose(localRecordID: UUID) async throws {
        deletedGlucoseIDs.append(localRecordID)
    }

    func deleteMeal(localRecordID: UUID) async throws {
        deletedMealIDs.append(localRecordID)
    }
}
