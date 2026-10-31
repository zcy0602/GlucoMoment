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
        /// 检测到的开始时间比记录早多少分钟；0 表示按记录时间计算。
        /// 不发给模型（模型曾把方向说反），详情页会用固定文案说明
        var startShiftMinutes: Int = 0
        var response: Response
        var curve: Curve
        /// 峰值升幅在这批餐里从高到低排第几，1 是最高；模型说"较高""较低"要和它一致
        var peakRiseRank: Int = 0
        /// 本机餐食记录的 id，只在 App 里用来判断复盘之后有没有新的餐；不编码，不发给模型
        var recordID: UUID?
        /// 整餐碳水粗分为偏少、中等、偏多，模型说碳水多少只能照它写；没有条目的餐为 nil
        var carbsLevel: String?
        /// 稳糖分和实测升幅对不上时的说明，如"稳糖分高，升幅却靠前"；对得上为 nil。
        /// 模型只能用它说分数和实测的反差，不自己比较分数（曾把 89 和 90 说反）
        var scoreMismatch: String?

        private nonisolated enum CodingKeys: String, CodingKey {
            case id, date, weekday, period, title, foods, glycemicLoad, score, response, curve, peakRiseRank, carbsLevel,
                 scoreMismatch
        }
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
        /// 各组平均升幅最大和最小相差至少 `MealReviewPayloadBuilder.minimumClearDifference`；否则只能说"差别不大"
        var isClearDifference: Bool = false
    }

    /// 升幅最高和最低的几餐在食物上的共同点，计数在本地算好，供第一条"规律"引用
    nonisolated struct Pattern: Codable, Hashable, Sendable {
        nonisolated struct Counts: Codable, Hashable, Sendable {
            var refinedGrain: Int
            var addedSugar: Int
            var refinedOrSugar: Int
            var protein: Int
            var vegetable: Int
            var proteinOrVegetable: Int

            /// 键与字段名一致，占位符和 moreInTop / moreInBottom 都用它
            var byCategory: KeyValuePairs<String, Int> {
                [
                    "refinedGrain": refinedGrain, "addedSugar": addedSugar, "refinedOrSugar": refinedOrSugar,
                    "protein": protein, "vegetable": vegetable, "proteinOrVegetable": proteinOrVegetable,
                ]
            }
        }

        /// 高、低两组各几餐
        var groupSize: Int
        var topMealIds: [String]
        var bottomMealIds: [String]
        var top: Counts
        var bottom: Counts
        /// 最高那组比最低那组多至少 `minimumPatternDifference` 餐的类别（Counts 的字段名）
        var moreInTop: [String]
        /// 最低那组比最高那组多至少 `minimumPatternDifference` 餐的类别
        var moreInBottom: [String]
        var snackCount: Int
        var mealCount: Int
    }

    var summary: Summary
    var meals: [Meal]
    var comparisons: [Comparison]
    /// 餐数少于 `MealReviewPayloadBuilder.minimumPatternMealCount`，或高低两组没有明显不同的类别时为 nil
    var pattern: Pattern?
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
            if meal.peakRiseRank > 0 {
                // 排在后半的写"第几低"，避免"20 餐中第 16 高"这种说法
                let fromBottom = meals.count - meal.peakRiseRank + 1
                values["\(meal.id).riseRank"] = meal.peakRiseRank <= fromBottom
                    ? "\(meals.count) 餐中第 \(meal.peakRiseRank) 高"
                    : "\(meals.count) 餐中第 \(fromBottom) 低"
            }
            values["\(meal.id).carbs"] = "\(Int(meal.foods.reduce(0) { $0 + $1.carbohydratesGrams }.rounded()))"
            if let score = meal.score {
                values["\(meal.id).score"] = "\(score)"
            }
            if let carbsLevel = meal.carbsLevel {
                values["\(meal.id).carbsLevel"] = carbsLevel
            }
            if let rise2h = meal.response.rise2h {
                values["\(meal.id).rise2h"] = Self.decimal(rise2h)
            }
            if meal.startShiftMinutes > 0 {
                values["\(meal.id).startShift"] = "\(meal.startShiftMinutes)"
            }
        }
        if let pattern {
            values["P.size"] = "\(pattern.groupSize)"
            values["P.snack"] = "\(pattern.snackCount)"
            values["P.total"] = "\(pattern.mealCount)"
            for (key, counts) in [("top", pattern.top), ("bottom", pattern.bottom)] {
                for (category, count) in counts.byCategory {
                    values["P.\(key).\(category)"] = "\(count)"
                }
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
    /// 至少这么多餐才总结规律；高、低两组各取 1/3，最多 5 餐
    static let minimumPatternMealCount = 6
    static let maximumPatternGroupSize = 5
    /// 高低两组某类食物至少差这么多餐才算规律
    static let minimumPatternDifference = 2
    /// 分组平均升幅至少差这么多 mmol/L 才算明显不同
    static let minimumClearDifference = 0.5
    /// 整餐碳水低于前者算偏少，不低于后者算偏多（克）。只是粗分，用来约束模型的说法
    static let lowCarbsGrams = 30.0
    static let highCarbsGrams = 75.0
    /// 稳糖分不低于前者算高、不高于后者算低；升幅排在前 1/3 或后 1/3 才算反差
    static let highScore = 70
    static let lowScore = 30

    static func build(
        meals: [MealRecord],
        points: [GlucosePoint],
        targetRange: GlucoseTargetRange = .standard,
        calendar: Calendar = .current
    ) -> MealReviewPayload {
        var excludedLowMealCount = 0
        var analyzed: [(meal: MealRecord, response: MealGlucoseResponse)] = []
        let starts = meals.map(\.eatenAt)
        for meal in meals.sorted(by: { $0.eatenAt < $1.eatenAt }) {
            let adjacent = MealGlucoseResponseCalculator.adjacentMealStarts(of: meal.eatenAt, among: starts)
            guard let response = MealGlucoseResponseCalculator.response(
                recordedStart: meal.eatenAt,
                points: points,
                previousMealStart: adjacent.previous,
                nextMealStart: adjacent.next
            ) else {
                continue
            }
            if response.hasLowReading {
                excludedLowMealCount += 1
            } else {
                analyzed.append((meal, response))
            }
        }
        analyzed = Array(analyzed.suffix(maximumMealCount))

        var entries = analyzed.enumerated().map { index, item in
            makeMeal(id: "M\(index + 1)", meal: item.meal, response: item.response, calendar: calendar)
        }
        let ranking = entries.indices.sorted { entries[$0].response.peakRise > entries[$1].response.peakRise }
        for (rank, index) in ranking.enumerated() {
            entries[index].peakRiseRank = rank + 1
            entries[index].scoreMismatch = scoreMismatch(score: entries[index].score, rank: rank + 1, count: entries.count)
        }
        let scored = zip(entries, analyzed).map { entry, item in (entry: entry, breakdown: item.meal.stableScore) }

        return MealReviewPayload(
            summary: summary(of: points, targetRange: targetRange, calendar: calendar),
            meals: entries,
            comparisons: comparisons(of: scored),
            pattern: pattern(of: entries),
            excludedLowMealCount: excludedLowMealCount
        )
    }

    private static func scoreMismatch(score: Int?, rank: Int, count: Int) -> String? {
        guard let score, count >= 3 else { return nil }
        if score >= highScore, rank * 3 <= count { return "稳糖分高，升幅却靠前" }
        if score <= lowScore, rank * 3 > count * 2 { return "稳糖分低，升幅却靠后" }
        return nil
    }

    /// 按食物类别数：精制主食、添加糖、蛋白质（肉蛋鱼豆或乳制品）、蔬菜；没有类别的餐都不计入
    private static func pattern(of meals: [MealReviewPayload.Meal]) -> MealReviewPayload.Pattern? {
        guard meals.count >= minimumPatternMealCount else { return nil }
        let size = min(maximumPatternGroupSize, meals.count / 3)
        let ranked = meals.sorted { $0.peakRiseRank < $1.peakRiseRank }
        let top = Array(ranked.prefix(size))
        let bottom = Array(ranked.suffix(size))

        func counts(_ group: [MealReviewPayload.Meal]) -> MealReviewPayload.Pattern.Counts {
            func has(_ meal: MealReviewPayload.Meal, _ categories: Set<FoodCategory>) -> Bool {
                meal.foods.contains { $0.category.flatMap(FoodCategory.init(rawValue:)).map(categories.contains) ?? false }
            }
            let refined = group.map { has($0, [.refinedGrain]) }
            let sugar = group.map { has($0, [.addedSugar]) }
            let protein = group.map { has($0, [.protein, .dairy]) }
            let vegetable = group.map { has($0, [.vegetable]) }
            return MealReviewPayload.Pattern.Counts(
                refinedGrain: refined.count { $0 },
                addedSugar: sugar.count { $0 },
                refinedOrSugar: zip(refined, sugar).count { $0 || $1 },
                protein: protein.count { $0 },
                vegetable: vegetable.count { $0 },
                proteinOrVegetable: zip(protein, vegetable).count { $0 || $1 }
            )
        }

        let topCounts = counts(top)
        let bottomCounts = counts(bottom)
        let pairs = zip(topCounts.byCategory, bottomCounts.byCategory)
        let moreInTop = pairs.filter { $0.value - $1.value >= minimumPatternDifference }.map(\.0.key)
        let moreInBottom = pairs.filter { $1.value - $0.value >= minimumPatternDifference }.map(\.0.key)
        guard !moreInTop.isEmpty || !moreInBottom.isEmpty else { return nil }

        return MealReviewPayload.Pattern(
            groupSize: size,
            topMealIds: top.map(\.id),
            bottomMealIds: bottom.map(\.id),
            top: topCounts,
            bottom: bottomCounts,
            moreInTop: moreInTop,
            moreInBottom: moreInBottom,
            snackCount: meals.count { $0.period == MealPeriod.snack.rawValue },
            mealCount: meals.count
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
        let carbs = meal.items.reduce(0) { $0 + $1.carbohydratesGrams }
        let carbsLevel: String? = meal.items.isEmpty ? nil
            : carbs < lowCarbsGrams ? "偏少" : carbs >= highCarbsGrams ? "偏多" : "中等"
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
            ),
            recordID: meal.id,
            carbsLevel: carbsLevel
        )
    }

    private static func summary(
        of points: [GlucosePoint],
        targetRange: GlucoseTargetRange,
        calendar: Calendar
    ) -> MealReviewPayload.Summary {
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
            // 平均值已四舍五入到 0.1，留一点误差余量
            let averages = groups.map(\.averagePeakRise)
            result.append(MealReviewPayload.Comparison(
                id: "C\(result.count + 1)",
                title: definition.title,
                groups: groups,
                isSufficient: groups.allSatisfy { $0.mealIds.count >= minimumGroupSize },
                isClearDifference: (averages.max() ?? 0) - (averages.min() ?? 0) >= minimumClearDifference - 0.001
            ))
        }
        return result
    }

    private static func key(for period: MealPeriod) -> String {
        switch period {
        case .breakfast: "breakfast"
        case .lunch: "lunch"
        case .dinner: "dinner"
        case .snack: "snack"
        }
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
