//
//  SwiftDataMealRepository.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataMealRepository: MealRepository {
  private let modelContext: ModelContext

  init(modelContainer: ModelContainer) {
    modelContext = modelContainer.mainContext
  }

  func meals(in interval: DateInterval, period: MealPeriod?) throws -> [MealRecord] {
    let start = interval.start
    let end = interval.end
    let descriptor: FetchDescriptor<MealRecordEntity>

    if let period {
      let periodRawValue = period.rawValue
      let predicate = #Predicate<MealRecordEntity> {
        $0.eatenAt >= start
          && $0.eatenAt < end
          && $0.mealPeriodRawValue == periodRawValue
      }
      descriptor = FetchDescriptor(
        predicate: predicate,
        sortBy: [SortDescriptor(\.eatenAt, order: .reverse)]
      )
    } else {
      let predicate = #Predicate<MealRecordEntity> {
        $0.eatenAt >= start && $0.eatenAt < end
      }
      descriptor = FetchDescriptor(
        predicate: predicate,
        sortBy: [SortDescriptor(\.eatenAt, order: .reverse)]
      )
    }

    var descriptorWithPrefetch = descriptor
    descriptorWithPrefetch.relationshipKeyPathsForPrefetching = [\.items]
    return try modelContext.fetch(descriptorWithPrefetch).map { entity in
      makeRecord(from: entity, snapshot: try fetchSnapshot(mealID: entity.id))
    }
  }

  func save(_ meal: MealRecord) throws {
    let mealID = meal.id
    let predicate = #Predicate<MealRecordEntity> { $0.id == mealID }
    var descriptor = FetchDescriptor<MealRecordEntity>(predicate: predicate)
    descriptor.fetchLimit = 1

    if let entity = try modelContext.fetch(descriptor).first {
      update(entity, from: meal)
    } else {
      modelContext.insert(makeEntity(from: meal))
    }
    try upsertSnapshot(from: meal)

    try modelContext.save()
  }

  func delete(id: UUID) throws {
    let mealID = id
    let predicate = #Predicate<MealRecordEntity> { $0.id == mealID }
    var descriptor = FetchDescriptor<MealRecordEntity>(predicate: predicate)
    descriptor.fetchLimit = 1

    if let snapshot = try fetchSnapshot(mealID: mealID) {
      modelContext.delete(snapshot)
    }
    guard let entity = try modelContext.fetch(descriptor).first else {
      try modelContext.save()
      return
    }
    modelContext.delete(entity)
    try modelContext.save()
  }

  private func makeRecord(
    from entity: MealRecordEntity,
    snapshot: MealAnalysisSnapshotEntity?
  ) -> MealRecord {
    let itemDetails = decodeItemDetails(snapshot?.itemDetailsData)
    return MealRecord(
      id: entity.id,
      eatenAt: entity.eatenAt,
      mealPeriod: MealPeriod(rawValue: entity.mealPeriodRawValue) ?? .lunch,
      title: entity.title,
      source: MealSource(rawValue: entity.sourceRawValue) ?? .manual,
      userFoodContext: entity.userFoodContext,
      note: entity.note,
      caloriesKcal: entity.caloriesKcal,
      carbohydratesGrams: entity.carbohydratesGrams,
      proteinGrams: entity.proteinGrams,
      fatGrams: entity.fatGrams,
      fiberGrams: entity.fiberGrams,
      photoFilename: entity.photoFilename,
      aiProvider: entity.aiProvider,
      aiModel: entity.aiModel,
      promptVersion: entity.promptVersion,
      analysisConfidence: entity.analysisConfidence,
      glucoseImpact: snapshot?.glucoseImpact,
      score: snapshot?.score,
      suggestions: decodeStrings(snapshot?.suggestionsData),
      followUpQuestions: decodeStrings(snapshot?.followUpQuestionsData),
      uncertainties: decodeStrings(snapshot?.uncertaintiesData),
      items: entity.items
        .sorted { $0.sortOrder < $1.sortOrder }
        .map { makeItem(from: $0, details: itemDetails[$0.id]) }
    )
  }

  private func makeItem(
    from entity: MealFoodItemEntity,
    details: SnapshotItemDetails?
  ) -> MealFoodItem {
    MealFoodItem(
      id: entity.id,
      name: entity.name,
      portionDescription: entity.portionDescription,
      estimatedGrams: entity.estimatedGrams,
      caloriesKcal: entity.caloriesKcal,
      carbohydratesGrams: entity.carbohydratesGrams,
      proteinGrams: entity.proteinGrams,
      fatGrams: entity.fatGrams,
      fiberGrams: entity.fiberGrams,
      confidence: entity.confidence,
      evidence: details?.evidence,
      uncertainties: details?.uncertainties ?? [],
      isUserConfirmed: entity.isUserConfirmed
    )
  }

  private func makeEntity(from meal: MealRecord) -> MealRecordEntity {
    let now = Date.now
    let entity = MealRecordEntity(
      id: meal.id,
      eatenAt: meal.eatenAt,
      timeZoneIdentifier: TimeZone.current.identifier,
      mealPeriodRawValue: meal.mealPeriod.rawValue,
      title: meal.title,
      sourceRawValue: meal.source.rawValue,
      userFoodContext: meal.userFoodContext,
      note: meal.note,
      caloriesKcal: meal.caloriesKcal,
      carbohydratesGrams: meal.carbohydratesGrams,
      proteinGrams: meal.proteinGrams,
      fatGrams: meal.fatGrams,
      fiberGrams: meal.fiberGrams,
      photoFilename: meal.photoFilename,
      aiProvider: meal.aiProvider,
      aiModel: meal.aiModel,
      promptVersion: meal.promptVersion,
      analysisConfidence: meal.analysisConfidence,
      createdAt: now,
      updatedAt: now
    )
    entity.items = makeItemEntities(from: meal.items)
    return entity
  }

  private func update(_ entity: MealRecordEntity, from meal: MealRecord) {
    entity.eatenAt = meal.eatenAt
    entity.timeZoneIdentifier = TimeZone.current.identifier
    entity.mealPeriodRawValue = meal.mealPeriod.rawValue
    entity.title = meal.title
    entity.sourceRawValue = meal.source.rawValue
    entity.userFoodContext = meal.userFoodContext
    entity.note = meal.note
    entity.caloriesKcal = meal.caloriesKcal
    entity.carbohydratesGrams = meal.carbohydratesGrams
    entity.proteinGrams = meal.proteinGrams
    entity.fatGrams = meal.fatGrams
    entity.fiberGrams = meal.fiberGrams
    entity.photoFilename = meal.photoFilename
    entity.aiProvider = meal.aiProvider
    entity.aiModel = meal.aiModel
    entity.promptVersion = meal.promptVersion
    entity.analysisConfidence = meal.analysisConfidence
    entity.updatedAt = .now

    for item in entity.items {
      modelContext.delete(item)
    }
    entity.items = makeItemEntities(from: meal.items)
  }

  private func makeItemEntities(from items: [MealFoodItem]) -> [MealFoodItemEntity] {
    items.enumerated().map { index, item in
      MealFoodItemEntity(
        id: item.id,
        sortOrder: index,
        name: item.name,
        portionDescription: item.portionDescription,
        estimatedGrams: item.estimatedGrams,
        caloriesKcal: item.caloriesKcal,
        carbohydratesGrams: item.carbohydratesGrams,
        proteinGrams: item.proteinGrams,
        fatGrams: item.fatGrams,
        fiberGrams: item.fiberGrams,
        confidence: item.confidence,
        isUserConfirmed: item.isUserConfirmed
      )
    }
  }

  private func fetchSnapshot(mealID: UUID) throws -> MealAnalysisSnapshotEntity? {
    let predicate = #Predicate<MealAnalysisSnapshotEntity> { $0.mealID == mealID }
    var descriptor = FetchDescriptor<MealAnalysisSnapshotEntity>(predicate: predicate)
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  private func upsertSnapshot(from meal: MealRecord) throws {
    let itemDetailsData = encodeItemDetails(meal.items)
    let mealID = meal.id
    let predicate = #Predicate<MealAnalysisSnapshotEntity> { $0.mealID == mealID }
    var descriptor = FetchDescriptor<MealAnalysisSnapshotEntity>(predicate: predicate)
    descriptor.fetchLimit = 1

    if let snapshot = try modelContext.fetch(descriptor).first {
      snapshot.glucoseImpact = meal.glucoseImpact
      snapshot.score = meal.score
      snapshot.suggestionsData = encodeStrings(meal.suggestions)
      snapshot.followUpQuestionsData = encodeStrings(meal.followUpQuestions)
      snapshot.uncertaintiesData = encodeStrings(meal.uncertainties)
      snapshot.itemDetailsData = itemDetailsData
    } else {
      modelContext.insert(
        MealAnalysisSnapshotEntity(
          mealID: meal.id,
          glucoseImpact: meal.glucoseImpact,
          score: meal.score,
          suggestionsData: encodeStrings(meal.suggestions),
          followUpQuestionsData: encodeStrings(meal.followUpQuestions),
          uncertaintiesData: encodeStrings(meal.uncertainties),
          itemDetailsData: itemDetailsData
        )
      )
    }
  }

  private func encodeStrings(_ values: [String]) -> Data? {
    guard !values.isEmpty else { return nil }
    return try? JSONEncoder().encode(values)
  }

  private func decodeStrings(_ data: Data?) -> [String] {
    guard let data else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }

  private func encodeItemDetails(_ items: [MealFoodItem]) -> Data? {
    let details = items.map {
      SnapshotItemDetails(
        id: $0.id,
        evidence: $0.evidence,
        uncertainties: $0.uncertainties
      )
    }
    guard details.contains(where: { $0.evidence != nil || !$0.uncertainties.isEmpty }) else {
      return nil
    }
    return try? JSONEncoder().encode(details)
  }

  private func decodeItemDetails(_ data: Data?) -> [UUID: SnapshotItemDetails] {
    guard let data,
      let details = try? JSONDecoder().decode([SnapshotItemDetails].self, from: data)
    else {
      return [:]
    }
    return Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
  }
}

private struct SnapshotItemDetails: Codable {
  let id: UUID
  let evidence: String?
  let uncertainties: [String]
}
