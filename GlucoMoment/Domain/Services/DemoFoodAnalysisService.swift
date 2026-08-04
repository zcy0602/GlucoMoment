//
//  DemoFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

struct DemoFoodAnalysisService: FoodAnalysisService {
    func analyze(
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        try await Task.sleep(for: .milliseconds(650))
        try Task.checkCancellation()

        let trimmedContext = userFoodContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = if let trimmedContext, !trimmedContext.isEmpty {
            "结合照片和用户补充：\(trimmedContext)"
        } else {
            "根据照片中的外观估算"
        }

        return FoodRecognitionResult(
            name: "鸡胸藜麦沙拉",
            confidence: 0.92,
            glucoseImpact: "中等",
            score: 82,
            items: [
                FoodRecognitionItem(
                    name: "鸡胸肉",
                    portionDescription: "约一掌大小",
                    estimatedGrams: 120,
                    caloriesKcal: 198,
                    carbohydratesGrams: 0,
                    proteinGrams: 32,
                    fatGrams: 7,
                    fiberGrams: 0,
                    confidence: 0.94,
                    evidence: evidence
                ),
                FoodRecognitionItem(
                    name: "藜麦",
                    portionDescription: "约半碗",
                    estimatedGrams: 100,
                    caloriesKcal: 120,
                    carbohydratesGrams: 21,
                    proteinGrams: 4,
                    fatGrams: 2,
                    fiberGrams: 3,
                    confidence: 0.84,
                    evidence: evidence,
                    uncertainties: ["无法仅凭照片确认实际重量"]
                ),
                FoodRecognitionItem(
                    name: "蔬菜与牛油果",
                    portionDescription: "约一碗",
                    estimatedGrams: 180,
                    caloriesKcal: 132,
                    carbohydratesGrams: 24,
                    proteinGrams: 4,
                    fatGrams: 9,
                    fiberGrams: 8,
                    confidence: 0.79,
                    evidence: evidence,
                    uncertainties: ["酱汁与烹饪用油不可见"]
                )
            ],
            suggestions: [
                "确认酱汁和主食份量后，碳水估算会更可靠。",
                "蛋白质较充足，可以先吃鸡胸肉和蔬菜再吃主食。",
                "这是一项营养估算，不代替医疗或用药建议。"
            ],
            followUpQuestions: ["沙拉中是否添加了含糖酱汁？"],
            uncertainties: ["无法从单张照片确认隐藏的油、糖和全部配料。"],
            provider: "demo",
            model: "food-analysis-demo-v1",
            promptVersion: "food-analysis-v1"
        )
    }
}
