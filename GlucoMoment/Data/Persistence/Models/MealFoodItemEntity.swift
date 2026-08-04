//
//  MealFoodItemEntity.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@Model
final class MealFoodItemEntity {
    #Unique<MealFoodItemEntity>([\.id])

    var id: UUID
    var sortOrder: Int
    var name: String
    var portionDescription: String
    var estimatedGrams: Double
    var caloriesKcal: Double
    var carbohydratesGrams: Double
    var proteinGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var confidence: Double?
    var isUserConfirmed: Bool
    var meal: MealRecordEntity?

    init(
        id: UUID,
        sortOrder: Int,
        name: String,
        portionDescription: String,
        estimatedGrams: Double,
        caloriesKcal: Double,
        carbohydratesGrams: Double,
        proteinGrams: Double,
        fatGrams: Double,
        fiberGrams: Double,
        confidence: Double?,
        isUserConfirmed: Bool,
        meal: MealRecordEntity? = nil
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.name = name
        self.portionDescription = portionDescription
        self.estimatedGrams = estimatedGrams
        self.caloriesKcal = caloriesKcal
        self.carbohydratesGrams = carbohydratesGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.confidence = confidence
        self.isUserConfirmed = isUserConfirmed
        self.meal = meal
    }
}
