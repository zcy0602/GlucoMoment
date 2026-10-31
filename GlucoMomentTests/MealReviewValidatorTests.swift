//
//  MealReviewValidatorTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

/// 数据见 `MealReviewPayloadBuilderTests.payload`：M1 午餐（升 4.6）、M2 晚餐白米饭套餐（升 5.5，开始时间提前 18 分钟）、
/// M3 午餐（升 0.6）；C1 按餐次、C2 按主食、C3 按蔬菜；另有 1 餐因低读数没有发送
@Suite("近期复盘的校验与渲染")
struct MealReviewValidatorTests {
    static let payload = MealReviewPayloadBuilderTests.payload

    @Test("占位符换成本地数值，只在占位符里出现的餐和比较也算作引用，并写出依据")
    func rendersValidItem() throws {
        let item = Self.item(
            "{M2.when}的{M2.title}峰值升幅 {M2.peakRise}，{C1.lunch.count} 次午餐平均 {C1.lunch}。餐后可以快走 30 分钟，再对照曲线看看。",
            guideline: "G4"
        )

        let valid = try MealReviewValidator.check(item, payload: Self.payload).get()

        #expect(valid.text == "10-21（周三）晚餐的白米饭套餐峰值升幅 5.5，2 次午餐平均 2.6。餐后可以快走 30 分钟，再对照曲线看看。")
        #expect(valid.mealIds == ["M2"])
        #expect(valid.comparisonIds == ["C1"])
        #expect(valid.guideline == .activityAfterMeals)
        #expect(valid.source == "依据：10-21（周三）晚餐 · 按餐次 · 食养指南原则四")
    }

    @Test("越界的条目被拒绝，并给出原因", arguments: [
        ("{M2.when}偏高。", [String](), "G9", MealReviewValidator.Rejection.unknownGuideline("G9")),
        ("{M2.when}偏高。", ["M9"], "G3a", .unknownReference("M9")),
        ("{M2.peakRiseX}偏高。", [], "G3a", .unknownPlaceholder("M2.peakRiseX")),
        ("{M2.peak rise}偏高。", ["M2"], "G3a", .unknownPlaceholder("{M2.peak ris")),
        ("多吃蔬菜。", [], "G1a", .noReference),
        ("{M2.when}主食导致升高。", [], "G3a", .bannedTerm("导致")),
        ("{M2.when}之后出现了低血糖。", [], "G3c", .bannedTerm("低血糖")),
        ("{M2.title}碳水不多。", [], "G3a", .bannedTerm("碳水不多")),
        ("{M2.title}和同天的{M3.title}差别不大。", [], "G3c", .bannedTerm("同天")),
        ("{M2.when}可以问问医生要不要调整用药。", [], "G3c", .bannedTerm("药")),
        ("{M2.when}的血糖升了 5.5。", [], "G3a", .rawNumber("了 5.5。")),
        ("M2 那一餐升幅 {M2.peakRise}。", [], "G3a", .rawNumber("M2 那一餐升幅")),
        ("{M2.when}的升幅是 ５.５。", [], "G3a", .rawNumber("是 ５.５。")),
    ])
    func rejects(text: String, mealIds: [String], guideline: String, expected: MealReviewValidator.Rejection) {
        let result = MealReviewValidator.check(Self.item(text, mealIds: mealIds, guideline: guideline), payload: Self.payload)
        #expect(result.failure == expected)
    }

    @Test("通用时长、1/3 和指南原话可以直接写；菜名里的字不参与禁词检查")
    func allowsAdviceNumbers() {
        let texts = [
            "{M2.when}之后，餐后 2 小时测一次血糖。",
            "{M2.when}主食里全谷物不到 1/3，可以换一部分杂粮。",
            "{M2.when}之后可以散步，运动前后留意血糖，避免低血糖。",
        ]
        for text in texts {
            #expect(MealReviewValidator.check(Self.item(text, guideline: "G3c"), payload: Self.payload).failure == nil, "\(text)")
        }
    }

    @Test("文字过长时拒绝")
    func rejectsLongText() {
        let text = "{M2.when}" + String(repeating: "很", count: MealReviewValidator.maxPlainTextLength + 1)
        #expect(MealReviewValidator.check(Self.item(text, guideline: "G3c"), payload: Self.payload).failure == .tooLong)
    }

    @Test("部分条目不合格时只丢掉那几条，并给出低读数的固定提醒")
    func keepsValidItems() {
        let draft = Self.draft([
            Self.item("{M2.when}的峰值升幅 {M2.peakRise}，可以把一部分主食换成杂粮再看看。", guideline: "G3a"),
            Self.item("{M2.when}主食导致升高。", guideline: "G3a"),
        ])

        let review = MealReviewValidator.review(from: draft, payload: Self.payload)

        #expect(review.items.count == 1)
        #expect(review.rejectedCount == 1)
        #expect(!review.isFallback)
        #expect(review.safetyNotice?.contains("最近有 1 餐") == true)
        #expect(review.provider == "test")
    }

    @Test("全部不合格时改用本地模板，模板的每一条都能通过校验")
    func fallsBackToTemplate() throws {
        let draft = Self.draft([Self.item("多吃蔬菜。", guideline: "G1a")])

        let review = MealReviewValidator.review(from: draft, payload: Self.payload)

        #expect(review.isFallback)
        #expect(review.rejectedCount == 1)
        #expect(review.items.count == MealReviewTemplate.items(for: Self.payload).count)
        #expect(review.items.count == 2)
        #expect(review.items.allSatisfy { !$0.text.contains("{") && !$0.text.contains("}") })
        #expect(review.items[0].text.hasPrefix("10-21（周三）晚餐的白米饭套餐峰值升幅 5.5"))
        #expect(review.items[1].text.contains("最平稳"))
    }

    @Test("没有低读数的餐时不显示安全提醒")
    func noSafetyNoticeWithoutLows() {
        var payload = Self.payload
        payload.excludedLowMealCount = 0
        #expect(MealReviewValidator.safetyNotice(for: payload) == nil)
    }

    @Test("规律那一条不管排第几都放到最前面，依据写升幅排名；只建议加餐的说法被拒，餐次名不拒")
    func patternItemComesFirst() throws {
        var payload = Self.payload
        let counts = MealReviewPayload.Pattern.Counts(
            refinedGrain: 1, addedSugar: 0, refinedOrSugar: 1, protein: 0, vegetable: 1, proteinOrVegetable: 1
        )
        payload.pattern = MealReviewPayload.Pattern(
            groupSize: 1, topMealIds: ["M2"], bottomMealIds: ["M3"], top: counts, bottom: counts,
            moreInTop: ["refinedGrain"], moreInBottom: [], snackCount: 2, mealCount: 3
        )
        let draft = Self.draft([
            Self.item("{M2.when}的{M2.title}升了 {M2.peakRise}。下次先吃菜。", guideline: "G3b"),
            Self.item("最近 {P.total} 餐里有 {P.snack} 次加餐。下次加餐选无糖的。", guideline: "G5"),
        ])

        let review = MealReviewValidator.review(from: draft, payload: payload)

        #expect(review.items.map(\.text) == ["最近 3 餐里有 2 次加餐。下次加餐选无糖的。", "10-21（周三）晚餐的白米饭套餐升了 5.5。下次先吃菜。"])
        #expect(review.items[0].source == "依据：最近 3 餐的升幅排名 · 食养指南原则五")
        #expect(MealReviewValidator.check(Self.item("{M2.when}之后建议加餐。", guideline: "G7"), payload: payload).failure == .bannedTerm("建议加餐"))
    }

    private static func item(_ text: String, mealIds: [String] = [], guideline: String) -> MealReviewDraftItem {
        MealReviewDraftItem(text: text, mealIds: mealIds, comparisonIds: [], guidelineId: guideline)
    }

    private static func draft(_ items: [MealReviewDraftItem]) -> MealReviewDraft {
        MealReviewDraft(items: items, provider: "test", model: "test-model", promptVersion: MealReviewPrompt.version)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
