//
//  DemoMeasuredFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

/// 演示模式的两段式识别：返回固定的「米饭 + 红烧肉盖浇」检测结果，营养按实测克重换算。
extension DemoFoodAnalysisService: MeasuredFoodAnalysisService {
    func detectFoods(
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodDetectionResult {
        try await Task.sleep(for: .milliseconds(500))
        try Task.checkCancellation()

        return FoodDetectionResult(
            mealName: "红烧肉盖饭",
            items: [
                FoodDetectedItem(
                    index: 0,
                    name: "米饭",
                    category: .staple,
                    box: FoodBoundingBox(minX: 0.22, minY: 0.3, maxX: 0.78, maxY: 0.7),
                    containerIndex: 0,
                    densityRange: 0.75...0.9,
                    confidence: 0.9
                ),
                FoodDetectedItem(
                    index: 1,
                    name: "红烧肉",
                    category: .meat,
                    box: FoodBoundingBox(minX: 0.4, minY: 0.4, maxX: 0.65, maxY: 0.6),
                    containerIndex: 0,
                    layeredOnIndex: 0,
                    layerThicknessCentimeters: 1...2,
                    densityRange: 0.75...1.0,
                    confidence: 0.85
                )
            ],
            containers: [
                FoodDetectedContainer(
                    index: 0,
                    type: .shallowBowl,
                    box: FoodBoundingBox(minX: 0.15, minY: 0.25, maxX: 0.85, maxY: 0.75)
                )
            ],
            uncertainties: ["演示数据：检测框为固定位置"],
            provider: "demo",
            model: "food-detect-demo-v1",
            promptVersion: QwenFoodAnalysisService.detectionPromptVersion
        )
    }

    func estimateNutrition(
        imageData: Data,
        detection: FoodDetectionResult,
        measurements: [FoodMeasuredItem],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        try await Task.sleep(for: .milliseconds(500))
        try Task.checkCancellation()

        let items = measurements.map { measured in
            let grams = measured.measurement.measuredGrams
            let per100 = DemoNutritionTable.per100Grams(
                name: measured.detection.name,
                category: measured.detection.category
            )
            let factor = grams / 100
            return FoodRecognitionItem(
                name: measured.detection.name,
                portionDescription: "LiDAR 实测约 \(Int(measured.measurement.volumeMilliliters.rounded())) ml",
                estimatedGrams: grams,
                caloriesKcal: per100.calories * factor,
                carbohydratesGrams: per100.carbohydrates * factor,
                proteinGrams: per100.protein * factor,
                fatGrams: per100.fat * factor,
                fiberGrams: per100.fiber * factor,
                confidence: 0.8,
                evidence: "演示数据：按实测克重和常见营养成分换算"
            )
        }

        let result = FoodRecognitionResult(
            name: detection.mealName,
            confidence: 0.82,
            glucoseImpact: "中等",
            score: 70,
            items: items,
            suggestions: [
                "可以先吃肉和蔬菜，再吃米饭，有助于餐后血糖平稳。",
                "这是一项营养估算，不代替医疗或用药建议。"
            ],
            followUpQuestions: ["红烧肉的酱汁是否偏甜？"],
            uncertainties: ["演示数据：营养素按常见做法估算"],
            provider: "demo",
            model: "food-measured-demo-v1",
            promptVersion: QwenFoodAnalysisService.measuredPromptVersion
        )

        return FoodMeasuredResultAssembler.assemble(
            result,
            itemIndices: measurements.map { Optional($0.detection.index) },
            measurements: measurements
        )
    }
}

private nonisolated enum DemoNutritionTable {
    struct Per100Grams {
        let calories: Double
        let carbohydrates: Double
        let protein: Double
        let fat: Double
        let fiber: Double
    }

    static func per100Grams(name: String, category: FoodCategory) -> Per100Grams {
        if name.contains("米饭") {
            return Per100Grams(calories: 116, carbohydrates: 25.9, protein: 2.6, fat: 0.3, fiber: 0.3)
        }
        if name.contains("红烧肉") {
            return Per100Grams(calories: 395, carbohydrates: 6, protein: 13, fat: 35, fiber: 0)
        }

        return switch category {
        case .staple:
            Per100Grams(calories: 130, carbohydrates: 28, protein: 3, fat: 0.5, fiber: 0.5)
        case .vegetable:
            Per100Grams(calories: 45, carbohydrates: 5, protein: 2, fat: 2.5, fiber: 2)
        case .meat:
            Per100Grams(calories: 220, carbohydrates: 3, protein: 20, fat: 14, fiber: 0)
        case .seafood:
            Per100Grams(calories: 110, carbohydrates: 1, protein: 19, fat: 3, fiber: 0)
        case .egg:
            Per100Grams(calories: 150, carbohydrates: 2, protein: 12, fat: 10, fiber: 0)
        case .soy:
            Per100Grams(calories: 85, carbohydrates: 3, protein: 8, fat: 5, fiber: 0.5)
        case .soup, .beverage:
            Per100Grams(calories: 25, carbohydrates: 3, protein: 1, fat: 1, fiber: 0)
        case .fruit:
            Per100Grams(calories: 50, carbohydrates: 12, protein: 0.5, fat: 0.2, fiber: 1.5)
        case .snack:
            Per100Grams(calories: 450, carbohydrates: 55, protein: 7, fat: 22, fiber: 2)
        case .mixed, .other:
            Per100Grams(calories: 150, carbohydrates: 15, protein: 6, fat: 7, fiber: 1)
        }
    }
}
