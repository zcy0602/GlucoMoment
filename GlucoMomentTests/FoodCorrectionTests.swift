//
//  FoodCorrectionTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

@Suite("一句话修正")
struct FoodCorrectionTests {
    @Test("只改动提到的条目：修改保留 id 和原类别，新增追加在后，删除优先于修改")
    func patchApplication() throws {
        let current = Self.result
        var rice = Self.item(name: "白米饭", grams: 75, carbs: 19.5, category: nil)
        rice.id = UUID()
        let egg = Self.item(name: "卤蛋", grams: 50, carbs: 1, category: .protein)
        let patch = FoodCorrectionPatch(
            reply: "已把米饭改为半碗，并新增卤蛋。",
            mealName: "米饭小炒肉",
            updatedItems: [1: rice, 2: Self.item(name: "不该出现", grams: 1, carbs: 0, category: .other), 9: rice],
            addedItems: [egg],
            removedRefs: [2],
            followUpQuestions: ["小炒肉用油多吗？", "第二个", "第三个", "第四个"]
        )

        let outcome = try patch.apply(to: current)

        #expect(outcome.result.items.map(\.name) == ["白米饭", "青菜", "卤蛋"])
        #expect(outcome.result.items[0].id == current.items[0].id)
        #expect(outcome.result.items[0].estimatedGrams == 75)
        #expect(outcome.result.items[0].foodCategory == .refinedGrain)
        #expect(outcome.result.items[1] == current.items[2])
        #expect(outcome.changedItemIDs == [current.items[0].id, egg.id])
        #expect(outcome.result.name == "米饭小炒肉")
        #expect(outcome.result.followUpQuestions.count == 3)
        #expect(outcome.reply == "已把米饭改为半碗，并新增卤蛋。")
    }

    @Test("模型没有改动时保留原结果和追问，空回复给出提示")
    func emptyPatchKeepsResult() throws {
        let outcome = try FoodCorrectionPatch(reply: "  ", mealName: "").apply(to: Self.result)

        #expect(outcome.result == Self.result)
        #expect(outcome.changedItemIDs.isEmpty)
        #expect(outcome.reply.contains("没有找到需要修改的内容"))
    }

    @Test("删光所有条目时报错，不返回空记录")
    func removingEverythingThrows() {
        let patch = FoodCorrectionPatch(reply: "已删除。", removedRefs: [1, 2, 3])

        #expect(throws: FoodAnalysisError.self) {
            try patch.apply(to: Self.result)
        }
    }

    @Test("解码修正结果：ref 可以是字符串，缺少的数组按空处理，无效编号忽略")
    func payloadDecoding() throws {
        let json = """
        {"reply":"已修改","updatedItems":[{"ref":"1","name":"糙米饭","portionDescription":"半碗",\
        "foodCategory":"全谷杂豆","estimatedGramsMin":70,"estimatedGramsMax":80,"caloriesMin":80,"caloriesMax":90,\
        "carbsMin":17,"carbsMax":19,"proteinMin":2,"proteinMax":2,"fatMin":0.5,"fatMax":0.7,"fiberMin":1,\
        "fiberMax":1.4,"confidence":0.8,"evidence":"用户修正","uncertainties":[]}],"removedRefs":[3,"x"]}
        """
        let patch = try JSONDecoder()
            .decode(FoodCorrectionPayloadDTO.self, from: Data(json.utf8))
            .makePatch()

        let updated = try #require(patch.updatedItems[1])
        #expect(updated.name == "糙米饭")
        #expect(updated.estimatedGrams == 75)
        #expect(updated.foodCategory == .wholeGrainLegume)
        #expect(patch.addedItems.isEmpty)
        #expect(patch.removedRefs == [3])
        #expect(patch.followUpQuestions == nil)
    }

    @Test("当前记录按顺序编号，数值保留一位小数，未选类别写明")
    func recordJSON() throws {
        var result = Self.result
        result.items[1].foodCategory = nil
        result.items[1].carbohydratesGrams = 3.04

        let json = FoodCorrectionRecord.recordJSON(for: result)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let items = try #require(object["items"] as? [[String: Any]])

        #expect(object["mealName"] as? String == "米饭小炒肉")
        #expect(items.map { $0["ref"] as? Int } == [1, 2, 3])
        #expect(items[1]["foodCategory"] as? String == "未选择")
        #expect(items[1]["carbs"] as? Double == 3)
        #expect(items[0]["estimatedGrams"] as? Double == 150)
    }

    @Test("修正记录只保留最近 10 轮")
    func historyJSONKeepsRecentTurns() throws {
        let history = (1...12).map { FoodCorrectionTurn(instruction: "第 \($0) 次", reply: "好") }

        let json = FoodCorrectionRecord.historyJSON(history)
        let turns = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]])

        #expect(turns.count == 10)
        #expect(turns.first?["instruction"] == "第 3 次")
    }

    @Test("App 与代理的修正提示词和说明长度上限一致")
    func correctionPromptMatchesProxy() throws {
        let coreURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Backend/FoodAnalysisProxy/src/core.ts")
        let core = try String(contentsOf: coreURL, encoding: .utf8)

        let promptStart = try #require(core.range(of: "export const CORRECTION_SYSTEM_PROMPT = `"))
        let promptEnd = try #require(core.range(of: "`;", range: promptStart.upperBound..<core.endIndex))
        #expect(
            String(core[promptStart.upperBound..<promptEnd.lowerBound])
                == OpenAICompatibleFoodAnalysisService.correctionSystemPrompt
        )
        #expect(core.contains("export const MAX_CORRECTION_LENGTH = \(FoodCorrectionLimit.maxInstructionLength);"))
    }

    @Test("演示模式模拟“只吃了一半”“还有一个卤蛋”“没吃”")
    func demoCorrections() async throws {
        let service = DemoFoodAnalysisService()
        let current = try await service.analyze(images: [Data([0x01])], userFoodContext: nil, mealPeriod: .lunch)

        let halved = try await service.correct(Self.request(current, "藜麦只吃了一半，还有一个卤蛋"))
        #expect(halved.result.items.first { $0.name == "藜麦" }?.estimatedGrams == 50)
        #expect(halved.result.items.last?.name == "卤蛋")
        #expect(halved.changedItemIDs.count == 2)

        let removed = try await service.correct(Self.request(halved.result, "鸡胸肉没吃"))
        #expect(!removed.result.items.contains { $0.name == "鸡胸肉" })
        #expect(removed.result.items.count == halved.result.items.count - 1)

        let unknown = try await service.correct(Self.request(current, "酱汁是油醋汁"))
        #expect(unknown.result == current)
        #expect(unknown.reply.contains("演示模式"))
    }

    private static func request(_ current: FoodRecognitionResult, _ instruction: String) -> FoodCorrectionRequest {
        FoodCorrectionRequest(
            current: current,
            instruction: instruction,
            history: [],
            userFoodContext: nil,
            mealPeriod: .lunch
        )
    }

    private static func item(
        name: String,
        grams: Double,
        carbs: Double,
        category: FoodCategory?
    ) -> FoodRecognitionItem {
        FoodRecognitionItem(
            name: name,
            portionDescription: "一份",
            estimatedGrams: grams,
            caloriesKcal: grams,
            carbohydratesGrams: carbs,
            proteinGrams: 2,
            fatGrams: 1,
            fiberGrams: 0.5,
            confidence: 0.8,
            evidence: "照片",
            foodCategory: category
        )
    }

    private static let result = FoodRecognitionResult(
        name: "米饭小炒肉",
        confidence: 0.8,
        glucoseImpact: "中等",
        score: 60,
        items: [
            item(name: "米饭", grams: 150, carbs: 39, category: .refinedGrain),
            item(name: "小炒肉", grams: 120, carbs: 6, category: .protein),
            item(name: "青菜", grams: 100, carbs: 3, category: .vegetable)
        ],
        suggestions: [],
        followUpQuestions: ["米饭吃了多少？"],
        uncertainties: [],
        provider: "test",
        model: "test",
        promptVersion: "test"
    )
}
