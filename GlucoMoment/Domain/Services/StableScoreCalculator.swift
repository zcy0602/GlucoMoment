//
//  StableScoreCalculator.swift
//  GlucoMoment
//

import Foundation

/// 稳糖分的计算结果与构成，供界面逐项展示。
nonisolated struct StableScoreBreakdown: Hashable, Sendable {
    var score: Int
    /// 整餐血糖负荷（GL）
    var glycemicLoad: Double
    /// 按 WS/T 652—2019 第 7.2 条的 GL 分级：低 / 中等 / 较高
    var glucoseImpact: String
    var baseScore: Double
    var vegetableBonus: Double
    var proteinBonus: Double
    var wholeGrainBonus: Double
    var addedSugarPenalty: Double
    // 以下为计算中间量（克），供 `MealSuggestionEngine` 判断用
    /// 主食（精制谷物、全谷杂豆、薯类）的可利用碳水
    var stapleCarbs: Double
    var vegetableGrams: Double
    /// 添加糖类食物的可利用碳水
    var addedSugarCarbs: Double

    /// 主食可利用碳水达到全谷物规则的适用下限，视为这一餐有主食
    var hasStaple: Bool {
        stapleCarbs >= StableScoreCalculator.wholeGrainMinimumStapleCarbs
    }
}

/// 稳糖分公式 v0.1：整餐 GL 定基础分，膳食指南条目定加减分。
/// 依据与参数说明见 `验证分析/稳糖分公式方案_v0.1.md`，原型为 `验证分析/stable_score.py`；
/// 修改参数时两边同步，并更新 `StableScoreCalculatorTests` 的期望值。
nonisolated enum StableScoreCalculator {
    static let formulaVersion = "stable-score-v0.1"

    /// GL → 基础分的分段线性曲线。分界点 10、20 来自 WS/T 652—2019 第 7.2 条，各点的分数为团队设定。
    static let baseCurve: [(glycemicLoad: Double, score: Double)] = [
        (10, 85), (20, 70), (30, 55), (45, 30), (70, 10)
    ]
    static let minimumScore = 5
    static let maximumBonus = 5.0
    /// 食养指南：餐餐都应有蔬菜，每天应达 500 g；每餐 150 g 为团队设定
    static let vegetableTargetGrams = 150.0
    /// 食养指南：蛋白质供能比 15%～20%；每餐 20 g 为团队设定
    static let proteinTargetGrams = 20.0
    /// 食养指南：全谷物和杂豆类应占主食的 1/3 以上；主食可利用碳水不足 10 g 时不适用
    static let wholeGrainShare = 1.0 / 3.0
    static let wholeGrainMinimumStapleCarbs = 10.0
    /// WS/T 429—2013 3.4：限制精制糖摄入；每克扣 0.8 分、最多扣 20 分为团队设定
    static let addedSugarPenaltyPerGram = 0.8
    static let maximumAddedSugarPenalty = 20.0

    /// 任意一项缺少食物类别（旧版代理或其他服务商）时返回 nil，由调用方沿用模型估算的分数。
    static func calculate(items: [FoodRecognitionItem]) -> StableScoreBreakdown? {
        guard !items.isEmpty else { return nil }

        var glycemicLoad = 0.0
        var stapleCarbs = 0.0
        var wholeGrainCarbs = 0.0
        var addedSugarCarbs = 0.0
        var vegetableGrams = 0.0
        var protein = 0.0

        for item in items {
            guard let category = item.foodCategory else { return nil }
            // WS/T 652—2019 第 2 章：GL 按可利用碳水计算；carbs 为总碳水，扣除膳食纤维
            let availableCarbs = max(0, item.carbohydratesGrams - item.fiberGrams)
            glycemicLoad += category.representativeGI * availableCarbs / 100
            protein += max(0, item.proteinGrams)

            switch category {
            case .refinedGrain, .tuber:
                stapleCarbs += availableCarbs
            case .wholeGrainLegume:
                stapleCarbs += availableCarbs
                wholeGrainCarbs += availableCarbs
            case .addedSugar:
                addedSugarCarbs += availableCarbs
            case .vegetable:
                vegetableGrams += max(0, item.estimatedGrams)
            case .fruit, .dairy, .protein, .nutFat, .other:
                break
            }
        }

        let baseScore = interpolatedBaseScore(for: glycemicLoad)
        let vegetableBonus = maximumBonus * min(1, vegetableGrams / vegetableTargetGrams)
        let proteinBonus = maximumBonus * min(1, protein / proteinTargetGrams)
        let wholeGrainBonus = stapleCarbs >= wholeGrainMinimumStapleCarbs
            && wholeGrainCarbs / stapleCarbs >= wholeGrainShare ? maximumBonus : 0
        let addedSugarPenalty = min(maximumAddedSugarPenalty, addedSugarPenaltyPerGram * addedSugarCarbs)

        let total = (baseScore + vegetableBonus + proteinBonus + wholeGrainBonus - addedSugarPenalty).rounded()
        return StableScoreBreakdown(
            score: min(100, max(minimumScore, Int(total))),
            glycemicLoad: glycemicLoad,
            glucoseImpact: glucoseImpact(for: glycemicLoad),
            baseScore: baseScore,
            vegetableBonus: vegetableBonus,
            proteinBonus: proteinBonus,
            wholeGrainBonus: wholeGrainBonus,
            addedSugarPenalty: addedSugarPenalty,
            stapleCarbs: stapleCarbs,
            vegetableGrams: vegetableGrams,
            addedSugarCarbs: addedSugarCarbs
        )
    }

    /// WS/T 652—2019 第 7.2 条：GL <10 低，10≤GL≤20 中，>20 高。
    static func glucoseImpact(for glycemicLoad: Double) -> String {
        if glycemicLoad < 10 { return "低" }
        return glycemicLoad <= 20 ? "中等" : "较高"
    }

    static func interpolatedBaseScore(for glycemicLoad: Double) -> Double {
        guard let first = baseCurve.first, let last = baseCurve.last else { return 0 }
        if glycemicLoad <= first.glycemicLoad { return first.score }
        for (lower, upper) in zip(baseCurve, baseCurve.dropFirst()) where glycemicLoad <= upper.glycemicLoad {
            let fraction = (glycemicLoad - lower.glycemicLoad) / (upper.glycemicLoad - lower.glycemicLoad)
            return lower.score + (upper.score - lower.score) * fraction
        }
        return last.score
    }
}

nonisolated extension FoodCategory {
    /// 类别 GI 代表值，主要依据 WS/T 429—2013 附录 A（数据源自《中国食物成分表 2002》）
    var representativeGI: Double {
        switch self {
        case .refinedGrain: 80      // 馒头 88、大米饭 83、烙饼 80、大米粥 69
        case .wholeGrainLegume: 50  // 玉米 55、荞麦 54、小麦 41、扁豆 38、绿豆 27
        case .tuber: 55             // 马铃薯 62、甘薯 54、山药 51、芋头 48、藕粉 33
        case .addedSugar: 65        // 蔗糖 65
        case .fruit: 45             // 香蕉 52、葡萄 43、苹果 36
        case .dairy: 35             // 酸奶 48、牛奶 28
        case .vegetable: 25         // 四季豆 27；食养指南表 1.1 多数蔬菜为低 GI
        case .protein: 25           // 豆腐 32、豆腐干 24
        case .nutFat: 15            // 花生 14
        case .other: 55             // 低 / 中 GI 分界
        }
    }
}

nonisolated extension MealRecord {
    /// 按已保存的条目重新计算稳糖分构成；任一条目缺少类别（旧记录、健康 App 导入）时为 nil
    var stableScore: StableScoreBreakdown? {
        StableScoreCalculator.calculate(items: items.map { item in
            FoodRecognitionItem(
                id: item.id,
                name: item.name,
                portionDescription: item.portionDescription,
                estimatedGrams: item.estimatedGrams,
                caloriesKcal: item.caloriesKcal,
                carbohydratesGrams: item.carbohydratesGrams,
                proteinGrams: item.proteinGrams,
                fatGrams: item.fatGrams,
                fiberGrams: item.fiberGrams,
                confidence: item.confidence ?? 0,
                evidence: item.evidence ?? "",
                uncertainties: item.uncertainties,
                foodCategory: item.foodCategory
            )
        })
    }
}
