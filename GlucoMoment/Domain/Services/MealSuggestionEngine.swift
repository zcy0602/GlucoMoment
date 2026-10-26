//
//  MealSuggestionEngine.swift
//  GlucoMoment
//

import Foundation

/// 一条稳糖建议：文案与对应的指南条目
nonisolated struct MealSuggestion: Hashable, Sendable {
    var text: String
    var guideline: DietGuideline
}

/// 按固定规则生成稳糖建议：只使用稳糖分的计算结果，每条建议都对应 `DietGuideline` 中的一条。
/// 规则表与阈值说明见仓库外一层的 `交接_建议与AI复盘.md`，改规则时两边同步。
nonisolated enum MealSuggestionEngine {
    /// 识别页最多显示的条数，含最后固定的测血糖提醒
    static let maximumCount = 3
    /// 添加糖达到这个克数（约扣 8 分）时提示，为团队设定
    static let addedSugarThresholdGrams = 10.0
    /// 蔬菜不到稳糖分满分线的一半时提示偏少，为团队设定
    static let lowVegetableGrams = StableScoreCalculator.vegetableTargetGrams / 2
    /// WS/T 652—2019 第 7.2 条：GL > 20 为较高
    static let highGlycemicLoad = 20.0
    /// GL 达到中等（≥ 10）时提示餐后活动
    static let activityGlycemicLoad = 10.0

    /// 识别页：针对这一餐的建议。按优先级最多取 2 条，最后固定提醒测餐后血糖
    static func suggestions(for breakdown: StableScoreBreakdown) -> [MealSuggestion] {
        var candidates: [MealSuggestion] = []

        if breakdown.addedSugarCarbs >= addedSugarThresholdGrams {
            candidates.append(MealSuggestion(
                text: "这餐的添加糖约 \(grams(breakdown.addedSugarCarbs)) 克，稳糖分因此扣了 \(points(breakdown.addedSugarPenalty)) 分。下次可以选无糖饮品，甜点减量。",
                guideline: .lessSugarOilSalt
            ))
        }
        if lacksWholeGrain(breakdown) {
            candidates.append(MealSuggestion(
                text: "这餐 GL 约 \(grams(breakdown.glycemicLoad))（\(breakdown.glucoseImpact)），主食里全谷物和杂豆不到 1/3。下次可以换一部分杂粮饭，再对照餐后血糖看看。",
                guideline: .wholeGrainShare
            ))
        }
        if breakdown.hasStaple {
            if breakdown.vegetableGrams < lowVegetableGrams {
                candidates.append(MealSuggestion(
                    text: vegetableText(grams: breakdown.vegetableGrams),
                    guideline: .vegetablesEveryMeal
                ))
            } else {
                candidates.append(MealSuggestion(
                    text: "吃的时候可以先吃菜，最后吃主食，对餐后血糖更友好。",
                    guideline: .vegetablesFirst
                ))
            }
        }
        if breakdown.glycemicLoad >= activityGlycemicLoad {
            candidates.append(MealSuggestion(
                text: "饭后可以快走 30 分钟左右；运动前后留意血糖，避免低血糖。",
                guideline: .activityAfterMeals
            ))
        }

        return Array(candidates.prefix(maximumCount - 1)) + [
            MealSuggestion(
                text: "餐后 2 小时测一次血糖，看看这一餐对你的影响。",
                guideline: .monitorResponse
            )
        ]
    }

    /// 饮食页：根据今天已记录的餐提示接下来的一餐。只看能算出稳糖分的记录，
    /// 健康 App 导入或缺少类别的餐会跳过；没有触发规则时返回 nil，由调用方显示通用建议
    static func nextMealSuggestion(basedOn meals: [MealRecord]) -> MealSuggestion? {
        let analyzed = meals
            .compactMap { meal in meal.stableScore.map { (eatenAt: meal.eatenAt, breakdown: $0) } }
            .sorted { $0.eatenAt < $1.eatenAt }
            .map(\.breakdown)
        guard let latest = analyzed.last else { return nil }

        if latest.addedSugarCarbs >= addedSugarThresholdGrams {
            return MealSuggestion(
                text: "上一餐的添加糖约 \(grams(latest.addedSugarCarbs)) 克，下一餐可以选白水、淡茶等无糖饮品。",
                guideline: .lessSugarOilSalt
            )
        }
        if analyzed.contains(where: \.hasStaple), analyzed.allSatisfy({ $0.vegetableGrams <= 0 }) {
            let subject = analyzed.count == 1 ? "上一餐" : "今天记录的 \(analyzed.count) 餐都"
            return MealSuggestion(
                text: "\(subject)没有识别到蔬菜，下一餐可以多安排一份。",
                guideline: .vegetablesEveryMeal
            )
        }
        if lacksWholeGrain(latest) {
            return MealSuggestion(
                text: "上一餐 GL 约 \(grams(latest.glycemicLoad))，主食里全谷物和杂豆不到 1/3。下一餐可以换成杂粮饭，或加些杂豆。",
                guideline: .wholeGrainShare
            )
        }
        return nil
    }

    /// 有主食、整餐 GL 较高，且全谷物和杂豆不到主食的 1/3（没有拿到全谷物加分）
    private static func lacksWholeGrain(_ breakdown: StableScoreBreakdown) -> Bool {
        breakdown.hasStaple && breakdown.glycemicLoad > highGlycemicLoad && breakdown.wholeGrainBonus == 0
    }

    private static func vegetableText(grams vegetableGrams: Double) -> String {
        guard vegetableGrams > 0 else {
            return "这餐没有识别到蔬菜。指南建议餐餐都有蔬菜，下次可以加一份青菜。"
        }
        return "这餐蔬菜约 \(grams(vegetableGrams)) 克，偏少。指南建议餐餐都有蔬菜，一天吃到 500 克左右。"
    }

    private static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func points(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
