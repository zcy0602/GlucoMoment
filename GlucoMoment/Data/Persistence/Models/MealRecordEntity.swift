//
//  MealRecordEntity.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@Model
final class MealRecordEntity {
    #Unique<MealRecordEntity>([\.id])
    #Index<MealRecordEntity>([\.eatenAt], [\.mealPeriodRawValue, \.eatenAt])

    var id: UUID
    var eatenAt: Date
    var timeZoneIdentifier: String
    var mealPeriodRawValue: String
    var title: String
    var sourceRawValue: String
    var userFoodContext: String?
    var note: String?
    var caloriesKcal: Double
    var carbohydratesGrams: Double
    var proteinGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var photoFilename: String?
    var aiProvider: String?
    var aiModel: String?
    var promptVersion: String?
    var analysisConfidence: Double?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MealFoodItemEntity.meal)
    var items: [MealFoodItemEntity]

    init(
        id: UUID,
        eatenAt: Date,
        timeZoneIdentifier: String,
        mealPeriodRawValue: String,
        title: String,
        sourceRawValue: String,
        userFoodContext: String?,
        note: String?,
        caloriesKcal: Double,
        carbohydratesGrams: Double,
        proteinGrams: Double,
        fatGrams: Double,
        fiberGrams: Double,
        photoFilename: String?,
        aiProvider: String?,
        aiModel: String?,
        promptVersion: String?,
        analysisConfidence: Double?,
        createdAt: Date,
        updatedAt: Date,
        items: [MealFoodItemEntity] = []
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.mealPeriodRawValue = mealPeriodRawValue
        self.title = title
        self.sourceRawValue = sourceRawValue
        self.userFoodContext = userFoodContext
        self.note = note
        self.caloriesKcal = caloriesKcal
        self.carbohydratesGrams = carbohydratesGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.photoFilename = photoFilename
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.promptVersion = promptVersion
        self.analysisConfidence = analysisConfidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }
}
