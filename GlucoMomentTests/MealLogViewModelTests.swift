//
//  MealLogViewModelTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

@Suite("饮食页建议卡")
@MainActor
struct MealLogViewModelTests {
    typealias Fixture = SuggestionFixtures

    @Test("今天没有记录时显示当前餐次的通用建议和出处")
    func showsPeriodGuidance() {
        let viewModel = MealLogViewModel(repository: StubMealRepository(meals: []))
        viewModel.reload(referenceDate: Fixture.date(hour: 12))

        #expect(viewModel.suggestionTitle == "午餐建议")
        #expect(viewModel.suggestionText == DemoDataProvider.mealGuidances[.lunch]?.text)
        #expect(viewModel.suggestionTags == DemoDataProvider.mealGuidances[.lunch]?.tags)
        #expect(viewModel.suggestionCitation == "依据：成人糖尿病食养指南（2023 年版）原则三、四")
    }

    @Test("上一餐触发规则后改为下一餐提示；晚于当前时间的记录不参与")
    func switchesToNextMealTip() {
        let sugaryDrink = Fixture.meal(hour: 9, items: Fixture.sugaryDrinkItems)
        let viewModel = MealLogViewModel(repository: StubMealRepository(meals: [sugaryDrink]))

        viewModel.reload(referenceDate: Fixture.date(hour: 8))
        #expect(viewModel.suggestionTitle == "早餐建议")

        viewModel.reload(referenceDate: Fixture.date(hour: 12))
        #expect(viewModel.suggestionTitle == "下一餐提示")
        #expect(viewModel.suggestionText.hasPrefix("上一餐的添加糖约 50 克"))
        #expect(viewModel.suggestionTags == ["少糖少油盐"])
        #expect(viewModel.suggestionCitation == "依据：成人糖尿病食养指南（2023 年版）原则五")
    }

    @Test("每个餐次的通用建议都标了指南条目")
    func everyPeriodHasGuidelines() {
        for period in MealPeriod.allCases {
            let guidance = DemoDataProvider.mealGuidances[period]
            #expect(guidance?.text.isEmpty == false)
            #expect(guidance?.guidelines.isEmpty == false)
        }
    }
}

@MainActor
private final class StubMealRepository: MealRepository {
    private let storedMeals: [MealRecord]

    init(meals: [MealRecord]) {
        storedMeals = meals
    }

    func meals(in interval: DateInterval, period: MealPeriod?) throws -> [MealRecord] {
        storedMeals
    }

    func save(_ meal: MealRecord) async throws {}

    func delete(id: UUID) async throws {}
}
