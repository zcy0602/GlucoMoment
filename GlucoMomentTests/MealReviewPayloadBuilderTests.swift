//
//  MealReviewPayloadBuilderTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

@Suite("近期复盘的数据")
struct MealReviewPayloadBuilderTests {
    typealias Fixture = ResponseFixtures

    /// 10-20 午餐（健康 App 导入，无条目）、10-21 晚餐（白米饭无蔬菜，记录偏晚 18 分钟）、
    /// 10-22 午餐（鸡胸藜麦沙拉）、10-23 早餐（只有指尖血）、10-24 晚餐（餐后低于 3.9）
    static let payload: MealReviewPayload = {
        let importedLunch = Fixture.date(month: 10, day: 20, hour: 12)
        let refinedDinner = Fixture.date(month: 10, day: 21, hour: 20)
        let balancedLunch = Fixture.date(month: 10, day: 22, hour: 12)
        let sparseBreakfast = Fixture.date(month: 10, day: 23, hour: 8)
        let lowDinner = Fixture.date(month: 10, day: 24, hour: 19)

        let points = Fixture.points(Fixture.slightlyEarly, around: importedLunch)
            + Fixture.points(Fixture.earlyStart, around: refinedDinner)
            + Fixture.points(Fixture.steadyStart, around: balancedLunch)
            + [-30, 0, 120].map { GlucosePoint(time: sparseBreakfast.addingTimeInterval(Double($0) * 60), value: 6) }
            + Fixture.points(Fixture.lowAfterMeal, around: lowDinner)

        let meals = [
            meal(at: lowDinner, period: .dinner, items: SuggestionFixtures.balancedItems),
            meal(at: refinedDinner, period: .dinner, title: "白米饭套餐", items: [
                SuggestionFixtures.item(.refinedGrain, 200, carbs: 52, fiber: 0.6, protein: 5)
            ]),
            meal(at: sparseBreakfast, period: .breakfast, items: SuggestionFixtures.balancedItems),
            meal(at: balancedLunch, period: .lunch, title: "鸡胸藜麦沙拉", items: SuggestionFixtures.balancedItems),
            meal(at: importedLunch, period: .lunch, title: "健康 App 饮食记录", items: [], source: .healthKit),
        ]
        return MealReviewPayloadBuilder.build(meals: meals, points: points, calendar: Fixture.calendar)
    }()

    @Test("按时间编号；数据不足的餐跳过，餐后有低读数的餐不发送并计数")
    func selectsAndNumbersMeals() {
        let payload = Self.payload

        #expect(payload.meals.map(\.id) == ["M1", "M2", "M3"])
        #expect(payload.meals.map(\.title) == ["健康 App 饮食记录", "白米饭套餐", "鸡胸藜麦沙拉"])
        #expect(payload.excludedLowMealCount == 1)
        #expect(payload.summary.days == 5)
        #expect(payload.summary.readingCount == 111 * 4 + 3)
    }

    @Test("每餐带本地指标、开始时间修正、曲线和稳糖分")
    func mealEntries() throws {
        let dinner = try #require(Self.payload.meals.first { $0.id == "M2" })

        #expect(dinner.date == "10-21")
        #expect(dinner.weekday == "周三")
        #expect(dinner.period == "晚餐")
        #expect(dinner.startShiftMinutes == 18)
        #expect(dinner.response.baseline == 4.9)
        #expect(dinner.response.peakRise == 5.5)
        #expect(dinner.response.peakMinutes == 33)
        #expect(dinner.response.iAUC == 418)
        #expect(dinner.curve.minutesFromStart.first == -45)
        #expect(dinner.curve.mmol.count == 16)
        #expect(dinner.foods.first?.category == "精制谷物")
        #expect(dinner.glycemicLoad == 41.1)
        #expect(Self.payload.meals.first?.glycemicLoad == nil)
    }

    @Test("分组比较只在至少两组有餐时给出，并标明样本是否足够")
    func comparisons() {
        let comparisons = Self.payload.comparisons

        #expect(comparisons.map(\.title) == ["按餐次", "按主食", "按蔬菜"])
        #expect(comparisons.map(\.id) == ["C1", "C2", "C3"])
        #expect(comparisons.allSatisfy { !$0.isSufficient })
        #expect(comparisons[0].groups.map(\.key) == ["lunch", "dinner"])
        #expect(comparisons[0].groups[0].mealIds == ["M1", "M3"])
        #expect(comparisons[1].groups.map(\.mealIds) == [["M2"], ["M3"]])
    }

    @Test("占位符的值由本地数据生成")
    func placeholderValues() {
        let values = Self.payload.placeholderValues

        #expect(values["M2.peakRise"] == "5.5")
        #expect(values["M2.when"] == "10-21（周三）晚餐")
        #expect(values["M2.startShift"] == "18")
        #expect(values["M1.startShift"] == nil)
        #expect(values["C1.lunch"] == "2.6")
        #expect(values["C1.lunch.count"] == "2")
        #expect(values["M2.riseRank"] == "3 餐中第 1 高")
        #expect(Self.payload.meals.first { $0.id == "M2" }?.peakRiseRank == 1)
    }

    @Test("餐数不足 6 餐时不总结规律")
    func noPatternForFewMeals() {
        #expect(Self.payload.pattern == nil)
        #expect(Self.payload.placeholderValues["P.size"] == nil)
    }

    @Test("发给模型的 JSON 不含开始时间修正和样本不足的比较")
    func modelJSONOmitsShiftAndInsufficientComparisons() throws {
        let json = try MealReviewPrompt.payloadJSON(Self.payload)

        #expect(!json.contains("startShift"))
        #expect(json.contains("peakRiseRank"))
        #expect(json.contains(#""comparisons":[]"#))
    }

    @Test("发送的 JSON 不含精确日期、备注和补充描述")
    func payloadOmitsPrivateFields() throws {
        let json = String(decoding: try JSONEncoder().encode(Self.payload), as: UTF8.self)

        #expect(!json.contains("2026"))
        #expect(!json.contains("私人备注"))
        #expect(!json.contains("补充描述"))
    }

    private static func meal(
        at eatenAt: Date,
        period: MealPeriod,
        title: String = "测试餐",
        items: [FoodRecognitionItem],
        source: MealSource = .aiPhoto
    ) -> MealRecord {
        MealRecord(
            eatenAt: eatenAt,
            mealPeriod: period,
            title: title,
            source: source,
            userFoodContext: "补充描述",
            note: "私人备注",
            caloriesKcal: 0,
            carbohydratesGrams: items.reduce(0) { $0 + $1.carbohydratesGrams },
            proteinGrams: 0,
            fatGrams: 0,
            fiberGrams: 0,
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
}
