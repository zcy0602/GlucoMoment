//
//  MealRecord.swift
//  GlucoMoment
//

import Foundation

nonisolated enum MealSource: String, Codable, Sendable {
    case manual
    case aiPhoto
    case healthKit

    var label: String {
        switch self {
        case .manual:
            "手动记录"
        case .aiPhoto:
            "AI 图片识别"
        case .healthKit:
            "健康 App"
        }
    }
}

nonisolated struct MealNutritionAvailability: OptionSet, Hashable, Codable, Sendable {
    let rawValue: Int

    static let energy = Self(rawValue: 1 << 0)
    static let carbohydrates = Self(rawValue: 1 << 1)
    static let protein = Self(rawValue: 1 << 2)
    static let fat = Self(rawValue: 1 << 3)
    static let fiber = Self(rawValue: 1 << 4)
    static let all: Self = [.energy, .carbohydrates, .protein, .fat, .fiber]
}

nonisolated struct MealRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    var eatenAt: Date
    var mealPeriod: MealPeriod
    var title: String
    var source: MealSource
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
    var glucoseImpact: String?
    var score: Int?
    var suggestions: [String]
    var followUpQuestions: [String]
    var uncertainties: [String]
    var items: [MealFoodItem]
    var nutritionAvailability: MealNutritionAvailability

    init(
        id: UUID = UUID(),
        eatenAt: Date,
        mealPeriod: MealPeriod,
        title: String,
        source: MealSource,
        userFoodContext: String? = nil,
        note: String? = nil,
        caloriesKcal: Double,
        carbohydratesGrams: Double,
        proteinGrams: Double,
        fatGrams: Double,
        fiberGrams: Double,
        photoFilename: String? = nil,
        aiProvider: String? = nil,
        aiModel: String? = nil,
        promptVersion: String? = nil,
        analysisConfidence: Double? = nil,
        glucoseImpact: String? = nil,
        score: Int? = nil,
        suggestions: [String] = [],
        followUpQuestions: [String] = [],
        uncertainties: [String] = [],
        items: [MealFoodItem],
        nutritionAvailability: MealNutritionAvailability = .all
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.mealPeriod = mealPeriod
        self.title = title
        self.source = source
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
        self.glucoseImpact = glucoseImpact
        self.score = score
        self.suggestions = suggestions
        self.followUpQuestions = followUpQuestions
        self.uncertainties = uncertainties
        self.items = items
        self.nutritionAvailability = nutritionAvailability
    }
}

nonisolated struct MealFoodItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var portionDescription: String
    var estimatedGrams: Double
    var caloriesKcal: Double
    var carbohydratesGrams: Double
    var proteinGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var confidence: Double?
    var evidence: String?
    var uncertainties: [String]
    var isUserConfirmed: Bool
    /// 识别时的食物类别；旧记录和健康 App 导入的餐没有类别
    var foodCategory: FoodCategory?

    init(
        id: UUID = UUID(),
        name: String,
        portionDescription: String,
        estimatedGrams: Double,
        caloriesKcal: Double,
        carbohydratesGrams: Double,
        proteinGrams: Double,
        fatGrams: Double,
        fiberGrams: Double,
        confidence: Double? = nil,
        evidence: String? = nil,
        uncertainties: [String] = [],
        isUserConfirmed: Bool = true,
        foodCategory: FoodCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.estimatedGrams = estimatedGrams
        self.caloriesKcal = caloriesKcal
        self.carbohydratesGrams = carbohydratesGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.confidence = confidence
        self.evidence = evidence
        self.uncertainties = uncertainties
        self.isUserConfirmed = isUserConfirmed
        self.foodCategory = foodCategory
    }
}
