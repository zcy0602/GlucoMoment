//
//  MealRepositoryTests.swift
//  GlucoMomentTests
//

import Foundation
import SwiftData
import Testing

@testable import GlucoMoment

extension PersistenceRepositoryTests {
  @Suite("饮食仓库")
  @MainActor
  struct MealRepositoryTests {
    @Test("保存后可以按日期和餐次读取")
    func savesAndFetchesMeal() throws {
      let (container, repository) = try makeRepository()
      let eatenAt = Date(timeIntervalSince1970: 1_700_000_000)
      let meal = makeMeal(eatenAt: eatenAt, period: .lunch)

      try repository.save(meal)

      let interval = DateInterval(
        start: eatenAt.addingTimeInterval(-1),
        end: eatenAt.addingTimeInterval(1)
      )
      let lunchMeals = try repository.meals(in: interval, period: .lunch)
      let breakfastMeals = try repository.meals(in: interval, period: .breakfast)
      let stored = try #require(lunchMeals.first)

      #expect(lunchMeals.count == 1)
      #expect(breakfastMeals.isEmpty)
      #expect(stored.id == meal.id)
      #expect(stored.userFoodContext == "半碗米饭，鸡肉清炒")
      #expect(stored.glucoseImpact == "中等")
      #expect(stored.score == 82)
      #expect(stored.suggestions == ["先吃蔬菜和鸡肉。"])
      #expect(stored.followUpQuestions == ["是否添加了酱汁？"])
      #expect(stored.uncertainties == ["烹饪用油量未知"])
      #expect(stored.items.map(\.name) == ["糙米饭", "鸡胸肉"])
      #expect(stored.items.first?.evidence == "用户描述和照片")
      #expect(stored.items.first?.uncertainties == ["重量为视觉估算"])
      #expect(try container.mainContext.fetchCount(FetchDescriptor<MealRecordEntity>()) == 1)
      #expect(try container.mainContext.fetchCount(FetchDescriptor<MealFoodItemEntity>()) == 2)
      #expect(
        try container.mainContext.fetchCount(FetchDescriptor<MealAnalysisSnapshotEntity>()) == 1)
    }

    @Test("相同 ID 保存时更新主记录和食物项目")
    func updatesMealAndItems() throws {
      let (_, repository) = try makeRepository()
      let id = UUID()
      let eatenAt = Date(timeIntervalSince1970: 1_700_000_000)
      var meal = makeMeal(id: id, eatenAt: eatenAt, period: .lunch)
      try repository.save(meal)

      meal.title = "已校正的午餐"
      meal.carbohydratesGrams = 30
      meal.items = [
        MealFoodItem(
          name: "糙米饭",
          portionDescription: "三分之一碗",
          estimatedGrams: 70,
          caloriesKcal: 82,
          carbohydratesGrams: 18,
          proteinGrams: 2,
          fatGrams: 1,
          fiberGrams: 1
        )
      ]
      try repository.save(meal)

      let interval = DateInterval(
        start: eatenAt.addingTimeInterval(-1),
        end: eatenAt.addingTimeInterval(1)
      )
      let fetched = try repository.meals(in: interval, period: .lunch)
      let stored = try #require(fetched.first)

      #expect(fetched.count == 1)
      #expect(stored.title == "已校正的午餐")
      #expect(stored.items.count == 1)
      #expect(stored.items.first?.portionDescription == "三分之一碗")
    }

    @Test("删除餐食时级联删除食物项目")
    func cascadesDeleteToFoodItems() throws {
      let (container, repository) = try makeRepository()
      let eatenAt = Date(timeIntervalSince1970: 1_700_000_000)
      let meal = makeMeal(eatenAt: eatenAt, period: .dinner)
      try repository.save(meal)

      try repository.delete(id: meal.id)

      #expect(try container.mainContext.fetchCount(FetchDescriptor<MealRecordEntity>()) == 0)
      #expect(try container.mainContext.fetchCount(FetchDescriptor<MealFoodItemEntity>()) == 0)
      #expect(
        try container.mainContext.fetchCount(FetchDescriptor<MealAnalysisSnapshotEntity>()) == 0)
    }

    @Test("保存的餐食照片可以再次读取")
    func storesAndLoadsMealPhoto() async throws {
      let store = InMemoryMealPhotoStore()
      let original = Data([0xFF, 0xD8, 0xFF, 0xD9])
      let filename = try await store.saveJPEG(original, mealID: UUID())

      #expect(await store.jpegData(filename: filename) == original)
    }

    @Test("一餐的多张照片按顺序保存，删除主文件时一并删除", arguments: [true, false])
    func storesMultipleMealPhotos(usesLocalStore: Bool) async throws {
      let store: any MealPhotoStoring = usesLocalStore ? LocalMealPhotoStore() : InMemoryMealPhotoStore()
      let photos = [Data([0x01]), Data([0x02]), Data([0x03])]
      let mealID = UUID()
      let filename = try await store.saveJPEGs(photos, mealID: mealID)

      #expect(filename == "\(mealID.uuidString.lowercased()).jpg")
      #expect(await store.jpegData(filename: filename) == photos[0])
      #expect(await store.allJPEGData(primaryFilename: filename) == photos)

      await store.delete(filename: filename)
      #expect(await store.allJPEGData(primaryFilename: filename).isEmpty)
      #expect(
        await store.jpegData(
          filename: MealPhotoFilename.additional(primaryFilename: filename, position: 2)
        ) == nil
      )
    }

    private func makeRepository() throws -> (ModelContainer, SwiftDataMealRepository) {
      let container = PersistenceRepositoryTests.container
      try PersistenceRepositoryTests.resetStore()
      return (container, SwiftDataMealRepository(modelContainer: container))
    }

    private func makeMeal(
      id: UUID = UUID(),
      eatenAt: Date,
      period: MealPeriod
    ) -> MealRecord {
      MealRecord(
        id: id,
        eatenAt: eatenAt,
        mealPeriod: period,
        title: "糙米鸡胸肉",
        source: .aiPhoto,
        userFoodContext: "半碗米饭，鸡肉清炒",
        note: "测试记录",
        caloriesKcal: 380,
        carbohydratesGrams: 42,
        proteinGrams: 34,
        fatGrams: 9,
        fiberGrams: 5,
        photoFilename: "meal.jpg",
        aiProvider: "demo",
        aiModel: "test-model",
        promptVersion: "food-analysis-v1",
        analysisConfidence: 0.88,
        glucoseImpact: "中等",
        score: 82,
        suggestions: ["先吃蔬菜和鸡肉。"],
        followUpQuestions: ["是否添加了酱汁？"],
        uncertainties: ["烹饪用油量未知"],
        items: [
          MealFoodItem(
            name: "糙米饭",
            portionDescription: "半碗",
            estimatedGrams: 100,
            caloriesKcal: 116,
            carbohydratesGrams: 25,
            proteinGrams: 3,
            fatGrams: 1,
            fiberGrams: 2,
            confidence: 0.9,
            evidence: "用户描述和照片",
            uncertainties: ["重量为视觉估算"]
          ),
          MealFoodItem(
            name: "鸡胸肉",
            portionDescription: "一掌大小",
            estimatedGrams: 120,
            caloriesKcal: 198,
            carbohydratesGrams: 0,
            proteinGrams: 32,
            fatGrams: 7,
            fiberGrams: 0,
            confidence: 0.94
          ),
        ]
      )
    }
  }
}
