//
//  MealSuggestionEngineTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

/// 规则表见仓库外一层的 `交接_建议与AI复盘.md`，改规则时两边同步。
@Suite("稳糖建议规则")
struct MealSuggestionEngineTests {
    typealias Fixture = SuggestionFixtures

    @Test("演示餐有蔬菜和全谷物：提示进餐顺序和餐后活动，最后提醒测血糖")
    func balancedMeal() throws {
        let breakdown = try #require(StableScoreCalculator.calculate(items: Fixture.balancedItems))
        let suggestions = MealSuggestionEngine.suggestions(for: breakdown)

        #expect(suggestions.map(\.guideline) == [.vegetablesFirst, .activityAfterMeals, .monitorResponse])
    }

    @Test("白米饭配少量青菜：提示换杂粮和补蔬菜，写出 GL 和蔬菜克数")
    func refinedStapleWithFewVegetables() throws {
        let breakdown = try #require(StableScoreCalculator.calculate(items: [
            Fixture.item(.refinedGrain, 200, carbs: 52, fiber: 0.6, protein: 5),
            Fixture.item(.vegetable, 50, carbs: 2, fiber: 1, protein: 1)
        ]))
        let suggestions = MealSuggestionEngine.suggestions(for: breakdown)

        // GL = 80 × 51.4 ÷ 100 + 25 × 1 ÷ 100 ≈ 41.4；餐后活动排在第 4，被 3 条上限截掉
        #expect(suggestions.map(\.guideline) == [.wholeGrainShare, .vegetablesEveryMeal, .monitorResponse])
        #expect(suggestions[0].text.contains("GL 约 41（较高）"))
        #expect(suggestions[1].text.contains("蔬菜约 50 克"))
    }

    @Test("全糖奶茶：先提示添加糖并写出克数和扣分；没有主食时不提蔬菜")
    func sugaryDrink() throws {
        let breakdown = try #require(StableScoreCalculator.calculate(items: Fixture.sugaryDrinkItems))
        let suggestions = MealSuggestionEngine.suggestions(for: breakdown)

        #expect(suggestions.map(\.guideline) == [.lessSugarOilSalt, .activityAfterMeals, .monitorResponse])
        #expect(suggestions[0].text.contains("添加糖约 50 克"))
        #expect(suggestions[0].text.contains("扣了 20 分"))
    }

    @Test("牛排蔬菜沙拉：GL 低又没有主食，只提醒测血糖")
    func lowGlycemicMealWithoutStaple() throws {
        let breakdown = try #require(StableScoreCalculator.calculate(items: [
            Fixture.item(.protein, 150, carbs: 0, fiber: 0, protein: 40),
            Fixture.item(.vegetable, 200, carbs: 10, fiber: 4, protein: 3)
        ]))

        #expect(MealSuggestionEngine.suggestions(for: breakdown).map(\.guideline) == [.monitorResponse])
    }

    @Test("能计算稳糖分时用规则建议，并写明对应的指南原则")
    func usesRuleSuggestions() {
        let result = Fixture.result(items: Fixture.sugaryDrinkItems, suggestions: ["模型建议"])

        #expect(result.effectiveSuggestions.count == 3)
        #expect(!result.effectiveSuggestions.contains("模型建议"))
        #expect(result.suggestionCitation == "依据：成人糖尿病食养指南（2023 年版）原则三、四、五")
    }

    @Test("缺少食物类别时沿用模型的建议，也不显示出处")
    func fallsBackToModelSuggestions() {
        var uncategorized = Fixture.item(.vegetable, 100, carbs: 5, fiber: 2, protein: 1)
        uncategorized.foodCategory = nil
        let result = Fixture.result(items: [uncategorized], suggestions: ["模型建议"])

        #expect(result.ruleSuggestions == nil)
        #expect(result.effectiveSuggestions == ["模型建议"])
        #expect(result.suggestionCitation == nil)
    }

    @Test("出处按原则序号排序并去重，没有条目时只写指南名称")
    func citationFormatting() {
        #expect(
            DietGuideline.citation(for: [.activityAfterMeals, .wholeGrainShare, .vegetablesFirst])
                == "依据：成人糖尿病食养指南（2023 年版）原则三、四"
        )
        #expect(DietGuideline.citation(for: []) == "依据：成人糖尿病食养指南（2023 年版）")
    }

    @Test("饮食页：按进餐时间取上一餐，添加糖较多时提示下一餐选无糖饮品")
    func nextMealAfterSugaryDrink() {
        let meals = [
            Fixture.meal(hour: 15, items: Fixture.sugaryDrinkItems),
            Fixture.meal(hour: 8, items: Fixture.balancedItems)
        ]
        let suggestion = MealSuggestionEngine.nextMealSuggestion(basedOn: meals)

        #expect(suggestion?.guideline == .lessSugarOilSalt)
        #expect(suggestion?.text.contains("约 50 克") == true)
    }

    @Test("饮食页：今天记录的餐都没有蔬菜时，提示下一餐补一份")
    func nextMealWithoutVegetables() {
        let meals = [
            Fixture.meal(hour: 8, items: [Fixture.item(.refinedGrain, 100, carbs: 50, fiber: 1, protein: 7)]),
            Fixture.meal(hour: 12, items: [
                Fixture.item(.refinedGrain, 150, carbs: 39, fiber: 0.5, protein: 4),
                Fixture.item(.protein, 100, carbs: 0, fiber: 0, protein: 23)
            ])
        ]
        let suggestion = MealSuggestionEngine.nextMealSuggestion(basedOn: meals)

        #expect(suggestion?.guideline == .vegetablesEveryMeal)
        #expect(suggestion?.text.hasPrefix("今天记录的 2 餐都没有识别到蔬菜") == true)
    }

    @Test("饮食页：上一餐 GL 较高且没有全谷物时，提示下一餐换杂粮")
    func nextMealAfterRefinedStaple() {
        let meals = [
            Fixture.meal(hour: 12, items: [
                Fixture.item(.refinedGrain, 200, carbs: 52, fiber: 0.6, protein: 5),
                Fixture.item(.vegetable, 150, carbs: 6, fiber: 2.5, protein: 2)
            ])
        ]

        #expect(MealSuggestionEngine.nextMealSuggestion(basedOn: meals)?.guideline == .wholeGrainShare)
    }

    @Test("饮食页：健康 App 导入和缺少类别的餐不参与判断，没有触发规则时返回 nil")
    func nextMealIgnoresUnscoredMeals() {
        var uncategorized = Fixture.item(.refinedGrain, 200, carbs: 52, fiber: 0.6, protein: 5)
        uncategorized.foodCategory = nil
        let unscored = [
            Fixture.meal(hour: 8, items: [], source: .healthKit),
            Fixture.meal(hour: 12, items: [uncategorized])
        ]

        #expect(MealSuggestionEngine.nextMealSuggestion(basedOn: unscored) == nil)
        #expect(MealSuggestionEngine.nextMealSuggestion(basedOn: [Fixture.meal(hour: 12, items: Fixture.balancedItems)]) == nil)
    }
}

/// 建议相关测试共用的餐食样例
enum SuggestionFixtures {
    /// 演示模式的鸡胸藜麦沙拉
    static let balancedItems = [
        item(.protein, 120, carbs: 0, fiber: 0, protein: 32),
        item(.wholeGrainLegume, 100, carbs: 21, fiber: 3, protein: 4),
        item(.vegetable, 180, carbs: 24, fiber: 8, protein: 4)
    ]

    static let sugaryDrinkItems = [
        item(.addedSugar, 500, carbs: 50, fiber: 0, protein: 3)
    ]

    /// 固定在同一天，避免测试结果随运行日期变化
    static func date(hour: Int) -> Date {
        let day = Date(timeIntervalSince1970: 1_761_436_800)
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static func item(
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

    static func meal(
        hour: Int,
        items: [FoodRecognitionItem],
        source: MealSource = .aiPhoto
    ) -> MealRecord {
        MealRecord(
            eatenAt: date(hour: hour),
            mealPeriod: MealPeriod.inferred(for: date(hour: hour)),
            title: "测试餐",
            source: source,
            caloriesKcal: 0,
            carbohydratesGrams: items.reduce(0) { $0 + $1.carbohydratesGrams },
            proteinGrams: items.reduce(0) { $0 + $1.proteinGrams },
            fatGrams: 0,
            fiberGrams: items.reduce(0) { $0 + $1.fiberGrams },
            items: items.map { item in
                MealFoodItem(
                    id: item.id,
                    name: item.name,
                    portionDescription: item.portionDescription,
                    estimatedGrams: item.estimatedGrams,
                    caloriesKcal: item.caloriesKcal,
                    carbohydratesGrams: item.carbohydratesGrams,
                    proteinGrams: item.proteinGrams,
                    fatGrams: item.fatGrams,
                    fiberGrams: item.fiberGrams,
                    foodCategory: item.foodCategory
                )
            }
        )
    }

    static func result(items: [FoodRecognitionItem], suggestions: [String]) -> FoodRecognitionResult {
        FoodRecognitionResult(
            name: "测试餐",
            confidence: 1,
            glucoseImpact: "中等",
            score: 70,
            items: items,
            suggestions: suggestions,
            followUpQuestions: [],
            uncertainties: [],
            provider: "test",
            model: "test",
            promptVersion: "test"
        )
    }
}
