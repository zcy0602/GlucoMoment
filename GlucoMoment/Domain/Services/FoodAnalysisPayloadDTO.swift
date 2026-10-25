//
//  FoodAnalysisPayloadDTO.swift
//  GlucoMoment
//

import Foundation

nonisolated struct FoodAnalysisPayloadDTO: Decodable, Sendable {
    let mealName: String
    let overallConfidence: Double
    let glucoseImpact: String
    let score: Int
    let items: [FoodAnalysisItemDTO]
    let followUpQuestions: [String]
    let suggestions: [String]
    let uncertainties: [String]

    func makeResult(provider: String, model: String, promptVersion: String) throws -> FoodRecognitionResult {
        guard !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !items.isEmpty,
              items.count <= 20 else {
            throw FoodAnalysisError.invalidResponse
        }

        return FoodRecognitionResult(
            name: mealName,
            confidence: overallConfidence.clamped(to: 0...1),
            glucoseImpact: glucoseImpact,
            score: score.clamped(to: 0...100),
            items: try items.map { try $0.result },
            suggestions: Array(suggestions.prefix(3)),
            followUpQuestions: Array(followUpQuestions.prefix(3)),
            uncertainties: Array(uncertainties.prefix(8)),
            provider: provider,
            model: model,
            promptVersion: promptVersion
        )
    }
}

nonisolated struct FoodAnalysisProxyResponseDTO: Decodable, Sendable {
    let provider: String
    let model: String
    let promptVersion: String
    let mealName: String
    let overallConfidence: Double
    let glucoseImpact: String
    let score: Int
    let items: [FoodAnalysisItemDTO]
    let followUpQuestions: [String]
    let suggestions: [String]
    let uncertainties: [String]

    func makeResult() throws -> FoodRecognitionResult {
        try FoodAnalysisPayloadDTO(
            mealName: mealName,
            overallConfidence: overallConfidence,
            glucoseImpact: glucoseImpact,
            score: score,
            items: items,
            followUpQuestions: followUpQuestions,
            suggestions: suggestions,
            uncertainties: uncertainties
        ).makeResult(provider: provider, model: model, promptVersion: promptVersion)
    }
}

nonisolated struct FoodAnalysisItemDTO: Decodable, Sendable {
    let name: String
    let portionDescription: String
    let foodCategory: String?
    let estimatedGramsMin: Double
    let estimatedGramsMax: Double
    let caloriesMin: Double
    let caloriesMax: Double
    let carbsMin: Double
    let carbsMax: Double
    let proteinMin: Double
    let proteinMax: Double
    let fatMin: Double
    let fatMax: Double
    let fiberMin: Double
    let fiberMax: Double
    let confidence: Double
    let evidence: String
    let uncertainties: [String]

    var result: FoodRecognitionItem {
        get throws {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  estimatedGramsMin >= 0, estimatedGramsMax >= 0,
                  caloriesMin >= 0, caloriesMax >= 0,
                  carbsMin >= 0, carbsMax >= 0,
                  proteinMin >= 0, proteinMax >= 0,
                  fatMin >= 0, fatMax >= 0,
                  fiberMin >= 0, fiberMax >= 0 else {
                throw FoodAnalysisError.invalidResponse
            }

            return FoodRecognitionItem(
                name: name,
                portionDescription: portionDescription,
                estimatedGrams: midpoint(estimatedGramsMin, estimatedGramsMax),
                caloriesKcal: midpoint(caloriesMin, caloriesMax),
                carbohydratesGrams: midpoint(carbsMin, carbsMax),
                proteinGrams: midpoint(proteinMin, proteinMax),
                fatGrams: midpoint(fatMin, fatMax),
                fiberGrams: midpoint(fiberMin, fiberMax),
                confidence: confidence.clamped(to: 0...1),
                evidence: evidence,
                uncertainties: Array(uncertainties.prefix(5)),
                foodCategory: FoodCategory(modelValue: foodCategory)
            )
        }
    }

    private func midpoint(_ first: Double, _ second: Double) -> Double {
        max(0, (min(first, second) + max(first, second)) / 2)
    }
}

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
