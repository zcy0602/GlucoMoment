//
//  FoodRecognitionResult.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/7/6.
//

import Foundation

nonisolated struct FoodRecognitionResult: Hashable, Sendable {
    var name: String
    var confidence: Double
    var glucoseImpact: String
    var score: Int
    var items: [FoodRecognitionItem]
    var suggestions: [String]
    var followUpQuestions: [String]
    var uncertainties: [String]
    var provider: String
    var model: String
    var promptVersion: String

    var caloriesKcal: Double {
        items.reduce(0) { $0 + $1.caloriesKcal }
    }

    var carbohydratesGrams: Double {
        items.reduce(0) { $0 + $1.carbohydratesGrams }
    }

    var proteinGrams: Double {
        items.reduce(0) { $0 + $1.proteinGrams }
    }

    var fatGrams: Double {
        items.reduce(0) { $0 + $1.fatGrams }
    }

    var fiberGrams: Double {
        items.reduce(0) { $0 + $1.fiberGrams }
    }

    var ingredients: [String] {
        items.map(\.name)
    }

    var confidenceText: String {
        confidence.formatted(.percent.precision(.fractionLength(0)))
    }

    var caloriesText: String {
        "\(caloriesKcal.formatted(.number.precision(.fractionLength(0)))) 千卡"
    }

    var carbohydratesText: String {
        "\(carbohydratesGrams.formatted(.number.precision(.fractionLength(0))))g"
    }

    var proteinText: String {
        "\(proteinGrams.formatted(.number.precision(.fractionLength(0))))g"
    }

    var fatText: String {
        "\(fatGrams.formatted(.number.precision(.fractionLength(0))))g"
    }
}

nonisolated struct FoodRecognitionItem: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var portionDescription: String
    var estimatedGrams: Double
    var caloriesKcal: Double
    var carbohydratesGrams: Double
    var proteinGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var confidence: Double
    var evidence: String
    var uncertainties: [String]

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
        confidence: Double,
        evidence: String,
        uncertainties: [String] = []
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
    }
}
