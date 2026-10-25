//
//  StableScoreCalculatorTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

/// 期望值与 `验证分析/stable_score.py` 的输出逐一对应，修改公式时两边同步。
@Suite("稳糖分公式")
struct StableScoreCalculatorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let items: [FoodRecognitionItem]
        let score: Int
        let glycemicLoad: Double
        let impact: String

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "白米饭 + 炒青菜 + 鸡胸", items: [
            item(.refinedGrain, 150, carbs: 39, fiber: 0.5, protein: 4),
            item(.vegetable, 200, carbs: 6, fiber: 2.5, protein: 3),
            item(.protein, 100, carbs: 0, fiber: 0, protein: 23)
        ], score: 62, glycemicLoad: 31.675, impact: "较高"),
        Case(name: "三分之一主食换成杂粮饭", items: [
            item(.refinedGrain, 100, carbs: 26, fiber: 0.3, protein: 2.7),
            item(.wholeGrainLegume, 60, carbs: 15.6, fiber: 1.8, protein: 1.8),
            item(.vegetable, 200, carbs: 6, fiber: 2.5, protein: 3),
            item(.protein, 100, carbs: 0, fiber: 0, protein: 23)
        ], score: 72, glycemicLoad: 28.335, impact: "较高"),
        Case(name: "白粥 + 咸菜", items: [
            item(.refinedGrain, 300, carbs: 30, fiber: 0.3, protein: 3),
            item(.vegetable, 20, carbs: 1, fiber: 0.3, protein: 0.3)
        ], score: 66, glycemicLoad: 23.935, impact: "较高"),
        Case(name: "两个馒头", items: [
            item(.refinedGrain, 200, carbs: 94, fiber: 2, protein: 14)
        ], score: 14, glycemicLoad: 73.6, impact: "较高"),
        Case(name: "全糖奶茶", items: [
            item(.addedSugar, 500, carbs: 50, fiber: 0, protein: 3)
        ], score: 32, glycemicLoad: 32.5, impact: "较高"),
        Case(name: "牛排蔬菜沙拉", items: [
            item(.protein, 150, carbs: 0, fiber: 0, protein: 40),
            item(.vegetable, 200, carbs: 10, fiber: 4, protein: 3)
        ], score: 95, glycemicLoad: 1.5, impact: "低"),
        Case(name: "一个苹果（GL 9.99 仍为低）", items: [
            item(.fruit, 200, carbs: 27, fiber: 4.8, protein: 0.5)
        ], score: 85, glycemicLoad: 9.99, impact: "低"),
        Case(name: "糖水铺：分数不低于下限", items: [
            item(.addedSugar, 500, carbs: 55, fiber: 1, protein: 2.5),
            item(.refinedGrain, 375, carbs: 70, fiber: 4.5, protein: 16)
        ], score: 5, glycemicLoad: 87.5, impact: "较高")
    ]

    @Test("典型餐的分数、GL 和标签与 Python 原型一致", arguments: cases)
    func matchesPrototype(_ testCase: Case) throws {
        let breakdown = try #require(StableScoreCalculator.calculate(items: testCase.items))
        #expect(breakdown.score == testCase.score)
        #expect(abs(breakdown.glycemicLoad - testCase.glycemicLoad) < 0.001)
        #expect(breakdown.glucoseImpact == testCase.impact)
    }

    @Test("分数构成：蔬菜、蛋白质、全谷物和添加糖各项")
    func breakdownComponents() throws {
        let mixed = try #require(StableScoreCalculator.calculate(items: Self.cases[1].items))
        #expect(mixed.vegetableBonus == 5)
        #expect(mixed.proteinBonus == 5)
        #expect(mixed.wholeGrainBonus == 5)
        #expect(mixed.addedSugarPenalty == 0)

        let milkTea = try #require(StableScoreCalculator.calculate(items: Self.cases[4].items))
        #expect(milkTea.addedSugarPenalty == 20)
        #expect(abs(milkTea.proteinBonus - 0.75) < 0.001)
    }

    @Test("GL 分级边界按 WS/T 652：<10 低，10～20 中等，>20 较高")
    func impactBoundaries() {
        #expect(StableScoreCalculator.glucoseImpact(for: 9.99) == "低")
        #expect(StableScoreCalculator.glucoseImpact(for: 10) == "中等")
        #expect(StableScoreCalculator.glucoseImpact(for: 20) == "中等")
        #expect(StableScoreCalculator.glucoseImpact(for: 20.01) == "较高")
    }

    @Test("基础分曲线在端点外取端点值")
    func baseCurveEnds() {
        #expect(StableScoreCalculator.interpolatedBaseScore(for: 0) == 85)
        #expect(StableScoreCalculator.interpolatedBaseScore(for: 25) == 62.5)
        #expect(StableScoreCalculator.interpolatedBaseScore(for: 200) == 10)
    }

    @Test("缺少食物类别或没有食物时不计算，由调用方沿用模型分数")
    func missingCategoryFallsBack() {
        var uncategorized = Self.item(.vegetable, 100, carbs: 5, fiber: 2, protein: 1)
        uncategorized.foodCategory = nil
        #expect(StableScoreCalculator.calculate(items: [uncategorized]) == nil)
        #expect(StableScoreCalculator.calculate(items: []) == nil)
    }

    private static func item(
        _ category: FoodCategory,
        _ grams: Double,
        carbs: Double,
        fiber: Double,
        protein: Double
    ) -> FoodRecognitionItem {
        FoodRecognitionItem(
            name: category.rawValue,
            portionDescription: "",
            estimatedGrams: grams,
            caloriesKcal: 0,
            carbohydratesGrams: carbs,
            proteinGrams: protein,
            fatGrams: 0,
            fiberGrams: fiber,
            confidence: 1,
            evidence: "测试",
            foodCategory: category
        )
    }
}
