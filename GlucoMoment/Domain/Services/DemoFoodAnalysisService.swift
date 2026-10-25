//
//  DemoFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

nonisolated struct DemoFoodAnalysisService: FoodAnalysisService {
    func analyze(
        images: [Data],
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
                    evidence: evidence,
                    foodCategory: .protein
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
                    uncertainties: ["无法仅凭照片确认实际重量"],
                    foodCategory: .wholeGrainLegume
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
                    uncertainties: ["酱汁与烹饪用油不可见"],
                    foodCategory: .vegetable
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

    /// 演示模式按关键词模拟三种常见说法：某样没吃、只吃了一半、还有一个鸡蛋
    func correct(_ request: FoodCorrectionRequest) async throws -> FoodCorrectionOutcome {
        try await Task.sleep(for: .milliseconds(650))
        try Task.checkCancellation()

        let instruction = request.instruction
        let items = request.current.items
        let mentioned = items.indices.first { index in
            Self.keywords(for: items[index].name).contains { instruction.contains($0) }
        }
        let removes = ["没吃", "没喝", "不是我", "去掉", "删掉"].contains { instruction.contains($0) }

        var patch = FoodCorrectionPatch(reply: "")
        var replies: [String] = []

        if removes, let mentioned {
            patch.removedRefs = [mentioned + 1]
            replies.append("已删除“\(items[mentioned].name)”")
        } else if instruction.contains("半"),
                  let index = mentioned ?? items.indices.max(by: {
                      items[$0].carbohydratesGrams < items[$1].carbohydratesGrams
                  }) {
            let halved = items[index].scaled(by: 0.5, note: instruction)
            patch.updatedItems[index + 1] = halved
            replies.append("已把“\(halved.name)”改为一半，约 \(Int(halved.estimatedGrams.rounded())) 克")
        }

        if !removes, instruction.contains("蛋"), !items.contains(where: { $0.name.contains("蛋") }) {
            patch.addedItems.append(
                FoodRecognitionItem(
                    name: "卤蛋",
                    portionDescription: "1 个",
                    estimatedGrams: 50,
                    caloriesKcal: 72,
                    carbohydratesGrams: 1,
                    proteinGrams: 6.5,
                    fatGrams: 4.8,
                    fiberGrams: 0,
                    confidence: 0.9,
                    evidence: "来自用户修正：\(instruction)",
                    foodCategory: .protein
                )
            )
            replies.append("已新增卤蛋 1 个")
        }

        patch.reply = replies.isEmpty
            ? "演示模式只能模拟“只吃了一半”“鸡胸肉没吃”“还有一个卤蛋”这几种说法，换成其中一种试试。"
            : replies.joined(separator: "，") + "。"
        return try patch.apply(to: request.current)
    }

    /// 名称本身及按“与、和、、”拆开的部分，用来判断用户说的是哪一样
    private static func keywords(for name: String) -> [String] {
        let parts = name.split(whereSeparator: { "与和、及".contains($0) }).map(String.init)
        return ([name] + parts).filter { $0.count >= 2 }
    }
}

private nonisolated extension FoodRecognitionItem {
    func scaled(by factor: Double, note: String) -> FoodRecognitionItem {
        var item = self
        item.estimatedGrams *= factor
        item.caloriesKcal *= factor
        item.carbohydratesGrams *= factor
        item.proteinGrams *= factor
        item.fatGrams *= factor
        item.fiberGrams *= factor
        item.portionDescription = "\(portionDescription)的一半"
        item.evidence = "来自用户修正：\(note)"
        return item
    }
}
