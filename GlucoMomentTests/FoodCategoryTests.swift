//
//  FoodCategoryTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

@Suite("食物类别与提示词 v2")
struct FoodCategoryTests {
    @Test("模型返回的类别去空白后映射，未知值归为其他，缺失时为空")
    func modelValueMapping() {
        #expect(FoodCategory(modelValue: "添加糖") == .addedSugar)
        #expect(FoodCategory(modelValue: "  蔬菜\n") == .vegetable)
        #expect(FoodCategory(modelValue: "零食") == .other)
        #expect(FoodCategory(modelValue: "") == nil)
        #expect(FoodCategory(modelValue: nil) == nil)
    }

    @Test("识别结果条目解码 foodCategory，旧版返回没有该字段时也能解析")
    func itemDecoding() throws {
        let withCategory = try decodeItem(extra: #","foodCategory":"精制谷物""#)
        #expect(withCategory.foodCategory == .refinedGrain)

        let withoutCategory = try decodeItem(extra: "")
        #expect(withoutCategory.foodCategory == nil)
    }

    @Test("App 与代理的系统提示词和类别取值保持一致")
    func promptMatchesProxy() throws {
        let coreURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Backend/FoodAnalysisProxy/src/core.ts")
        let core = try String(contentsOf: coreURL, encoding: .utf8)

        let promptStart = try #require(core.range(of: "export const SYSTEM_PROMPT = `"))
        let promptEnd = try #require(core.range(of: "`;", range: promptStart.upperBound..<core.endIndex))
        #expect(String(core[promptStart.upperBound..<promptEnd.lowerBound]) == OpenAICompatibleFoodAnalysisService.systemPrompt)

        let listStart = try #require(core.range(of: "export const FOOD_CATEGORIES = ["))
        let listEnd = try #require(core.range(of: "] as const;", range: listStart.upperBound..<core.endIndex))
        let proxyCategories = core[listStart.upperBound..<listEnd.lowerBound]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \",")) }
            .filter { !$0.isEmpty }
        #expect(proxyCategories == FoodCategory.allCases.map(\.rawValue))
    }

    @Test("App 与代理的照片张数上限一致")
    func imageLimitMatchesProxy() throws {
        let coreURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Backend/FoodAnalysisProxy/src/core.ts")
        let core = try String(contentsOf: coreURL, encoding: .utf8)

        #expect(core.contains("export const MAX_IMAGE_COUNT = \(FoodAnalysisImageLimit.maxImageCount);"))
    }

    private func decodeItem(extra: String) throws -> FoodRecognitionItem {
        let json = """
        {"name":"米饭","portionDescription":"一碗","estimatedGramsMin":140,"estimatedGramsMax":160,\
        "caloriesMin":160,"caloriesMax":190,"carbsMin":36,"carbsMax":42,"proteinMin":3,"proteinMax":4,\
        "fatMin":0,"fatMax":1,"fiberMin":0,"fiberMax":1,"confidence":0.8,"evidence":"照片",\
        "uncertainties":[]\(extra)}
        """
        let dto = try JSONDecoder().decode(FoodAnalysisItemDTO.self, from: Data(json.utf8))
        return try dto.result
    }
}
