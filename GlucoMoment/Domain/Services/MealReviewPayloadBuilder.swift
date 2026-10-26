//
//  MealReviewPayloadBuilder.swift
//  GlucoMoment
//

import Foundation

/// 近期复盘发给模型的数据：每餐的本地指标和曲线，加上本地算好的分组比较。
/// 不含照片、备注、补充描述和精确时间；数字都在本地算好，模型只引用不计算。
/// 设计见仓库外一层的 `交接_建议与AI复盘.md`（第三档 C3）。
nonisolated struct MealReviewPayload: Codable, Hashable, Sendable {
    nonisolated struct Summary: Codable, Hashable, Sendable {
        /// 有读数的天数
        var days: Int
        var readingCount: Int
        var average: Double
        var inRangePercentage: Int
    }

    nonisolated struct Food: Codable, Hashable, Sendable {
        var name: String
        var category: String?
        var carbohydratesGrams: Double
    }

    nonisolated struct Response: Codable, Hashable, Sendable {
        var baseline: Double
        var peak: Double
        var peakRise: Double
        var peakMinutes: Int
        var rise2h: Double?
        var iAUC: Int
    }

    nonisolated struct Curve: Codable, Hashable, Sendable {
        var minutesFromStart: [Int]
        var mmol: [Double?]
    }

    nonisolated struct Meal: Codable, Hashable, Sendable {
        /// M1、M2……按进餐时间先后编号
        var id: String
        /// 月-日，例如 10-21
        var date: String
        var weekday: String
        /// 记录时选的餐次
        var period: String
        var title: String
        var foods: [Food]
        var glycemicLoad: Double?
        var score: Int?
        /// 检测到的开始时间比记录早多少分钟；0 表示按记录时间计算
        var startShiftMinutes: Int
        var response: Response
        var curve: Curve
    }

    nonisolated struct Group: Codable, Hashable, Sendable {
        /// 占位符里用的英文键，例如 C2.refined
        var key: String
        var label: String
        var mealIds: [String]
        var averagePeakRise: Double
    }

    nonisolated struct Comparison: Codable, Hashable, Sendable {
        var id: String
        var title: String
        var groups: [Group]
        /// 每组都至少有 `MealReviewPayloadBuilder.minimumGroupSize` 餐；不足时只能说"样本还少"
        var isSufficient: Bool
    }

    var summary: Summary
    var meals: [Meal]
    var comparisons: [Comparison]
    /// 窗口内有低于 3.9 的读数、没有发给模型的餐数；App 另外显示固定的安全提示
    var excludedLowMealCount: Int

    /// 模型在文字里写占位符（如 {M1.peakRise}），由 App 用这里的值替换，数字不经过模型
    var placeholderValues: [String: String] {
        var values: [String: String] = [:]
        for meal in meals {
            values["\(meal.id).when"] = "\(meal.date)（\(meal.weekday)）\(meal.period)"
            values["\(meal.id).title"] = meal.title
            values["\(meal.id).baseline"] = Self.decimal(meal.response.baseline)
            values["\(meal.id).peak"] = Self.decimal(meal.response.peak)
            values["\(meal.id).peakRise"] = Self.decimal(meal.response.peakRise)
            values["\(meal.id).peakMinutes"] = "\(meal.response.peakMinutes)"
            values["\(meal.id).iAUC"] = "\(meal.response.iAUC)"
            if let rise2h = meal.response.rise2h {
                values["\(meal.id).rise2h"] = Self.decimal(rise2h)
            }
            if meal.startShiftMinutes > 0 {
                values["\(meal.id).startShift"] = "\(meal.startShiftMinutes)"
            }
        }
        for comparison in comparisons {
            for group in comparison.groups {
                values["\(comparison.id).\(group.key)"] = Self.decimal(group.averagePeakRise)
                values["\(comparison.id).\(group.key).count"] = "\(group.mealIds.count)"
            }
        }
        return values
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }
}

nonisolated enum MealReviewPayloadBuilder {
    /// 复盘统计最近多少天
    static let reviewDays = 14
    /// 最多发给模型的餐数，取最近的
    static let maximumMealCount = 20
    /// 分组比较时每组至少要有的餐数
    static let minimumGroupSize = 3
    /// 与 `GlucoseTargetRange.standard` 一致
    static let targetRange = 3.9...10.0

    static func build(
        meals: [MealRecord],
        points: [GlucosePoint],
        calendar: Calendar = .current
    ) -> MealReviewPayload {
        var excludedLowMealCount = 0
        var analyzed: [(meal: MealRecord, response: MealGlucoseResponse)] = []
        for meal in meals.sorted(by: { $0.eatenAt < $1.eatenAt }) {
            guard let response = MealGlucoseResponseCalculator.response(recordedStart: meal.eatenAt, points: points) else {
                continue
            }
            if response.hasLowReading {
                excludedLowMealCount += 1
            } else {
                analyzed.append((meal, response))
            }
        }
        analyzed = Array(analyzed.suffix(maximumMealCount))

        let entries = analyzed.enumerated().map { index, item in
            makeMeal(id: "M\(index + 1)", meal: item.meal, response: item.response, calendar: calendar)
        }
        let scored = zip(entries, analyzed).map { entry, item in (entry: entry, breakdown: item.meal.stableScore) }

        return MealReviewPayload(
            summary: summary(of: points, calendar: calendar),
            meals: entries,
            comparisons: comparisons(of: scored),
            excludedLowMealCount: excludedLowMealCount
        )
    }

    private static func makeMeal(
        id: String,
        meal: MealRecord,
        response: MealGlucoseResponse,
        calendar: Calendar
    ) -> MealReviewPayload.Meal {
        let components = calendar.dateComponents([.month, .day, .weekday], from: meal.eatenAt)
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        let breakdown = meal.stableScore
        return MealReviewPayload.Meal(
            id: id,
            date: String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0),
            weekday: "周\(weekdays[((components.weekday ?? 1) - 1) % 7])",
            period: meal.mealPeriod.rawValue,
            title: meal.title,
            foods: meal.items.map {
                MealReviewPayload.Food(
                    name: $0.name,
                    category: $0.foodCategory?.rawValue,
                    carbohydratesGrams: rounded($0.carbohydratesGrams)
                )
            },
            glycemicLoad: breakdown.map { rounded($0.glycemicLoad) },
            score: breakdown?.score ?? meal.score,
            startShiftMinutes: response.startShiftMinutes,
            response: MealReviewPayload.Response(
                baseline: rounded(response.baseline),
                peak: rounded(response.peak),
                peakRise: rounded(response.peakRise),
                peakMinutes: Int(response.peakMinutes.rounded()),
                rise2h: response.rise2h.map(rounded),
                iAUC: Int(response.iAUC.rounded())
            ),
            curve: MealReviewPayload.Curve(
                minutesFromStart: MealGlucoseResponseCalculator.curveOffsets,
                mmol: response.curve.map { $0.map(rounded) }
            )
        )
    }

    private static func summary(of points: [GlucosePoint], calendar: Calendar) -> MealReviewPayload.Summary {
        let values = points.map(\.value)
        let inRange = values.count { targetRange.contains($0) }
        return MealReviewPayload.Summary(
            days: Set(points.map { calendar.startOfDay(for: $0.time) }).count,
            readingCount: values.count,
            average: values.isEmpty ? 0 : rounded(values.reduce(0, +) / Double(values.count)),
            inRangePercentage: values.isEmpty ? 0 : Int((Double(inRange) / Double(values.count) * 100).rounded())
        )
    }

    /// 只在至少两组都有餐时给出比较；没有稳糖分构成（缺类别）的餐不参与按食物分组的比较
    private static func comparisons(
        of scored: [(entry: MealReviewPayload.Meal, breakdown: StableScoreBreakdown?)]
    ) -> [MealReviewPayload.Comparison] {
        typealias Rule = (key: String, label: String, includes: (MealReviewPayload.Meal, StableScoreBreakdown?) -> Bool)
        let definitions: [(title: String, rules: [Rule])] = [
            ("按餐次", MealPeriod.allCases.map { period in
                (key: key(for: period), label: period.rawValue, includes: { meal, _ in meal.period == period.rawValue })
            }),
            ("按主食", [
                ("refined", "全谷物不足 1/3", { _, b in b.map { $0.hasStaple && $0.wholeGrainBonus == 0 } ?? false }),
                ("wholeGrain", "全谷物达 1/3", { _, b in b.map { $0.hasStaple && $0.wholeGrainBonus > 0 } ?? false }),
            ]),
            ("按蔬菜", [
                ("fewVegetables", "蔬菜不足 75 克", { _, b in
                    b.map { $0.hasStaple && $0.vegetableGrams < MealSuggestionEngine.lowVegetableGrams } ?? false
                }),
                ("vegetables", "蔬菜 75 克以上", { _, b in
                    b.map { $0.hasStaple && $0.vegetableGrams >= MealSuggestionEngine.lowVegetableGrams } ?? false
                }),
            ]),
            ("按添加糖", [
                ("addedSugar", "添加糖 10 克以上", { _, b in
                    b.map { $0.addedSugarCarbs >= MealSuggestionEngine.addedSugarThresholdGrams } ?? false
                }),
                ("noAddedSugar", "添加糖不到 10 克", { _, b in
                    b.map { $0.addedSugarCarbs < MealSuggestionEngine.addedSugarThresholdGrams } ?? false
                }),
            ]),
        ]

        var result: [MealReviewPayload.Comparison] = []
        for definition in definitions {
            let groups: [MealReviewPayload.Group] = definition.rules.compactMap { rule in
                let members = scored.filter { rule.includes($0.entry, $0.breakdown) }.map(\.entry)
                guard !members.isEmpty else { return nil }
                let rises = members.map(\.response.peakRise)
                return MealReviewPayload.Group(
                    key: rule.key,
                    label: rule.label,
                    mealIds: members.map(\.id),
                    averagePeakRise: rounded(rises.reduce(0, +) / Double(rises.count))
                )
            }
            guard groups.count >= 2 else { continue }
            result.append(MealReviewPayload.Comparison(
                id: "C\(result.count + 1)",
                title: definition.title,
                groups: groups,
                isSufficient: groups.allSatisfy { $0.mealIds.count >= minimumGroupSize }
            ))
        }
        return result
    }

    private static func key(for period: MealPeriod) -> String {
        switch period {
        case .breakfast: "breakfast"
        case .lunch: "lunch"
        case .dinner: "dinner"
        }
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
