//
//  MealReviewValidator.swift
//  GlucoMoment
//

import Foundation

/// 校验并渲染后的近期复盘，界面直接显示
nonisolated struct MealReview: Codable, Hashable, Sendable {
    nonisolated struct Item: Codable, Hashable, Sendable {
        /// 占位符已替换为本地数值
        var text: String
        /// 例如「依据：10-21（周三）晚餐 · 按餐次 · 食养指南原则三」
        var source: String
        var guideline: DietGuideline
        /// 条目里实际引用的餐和比较，包括只在占位符里出现的
        var mealIds: [String]
        var comparisonIds: [String]
    }

    var items: [Item]
    /// 模型的条目全部没通过校验（或一条都没返回），改用本地模板
    var isFallback: Bool
    /// 没通过校验、被丢掉的条数
    var rejectedCount: Int
    /// 有餐后低读数的餐不发给模型，改由这段固定文案提醒
    var safetyNotice: String?
    var provider: String
    var model: String
    var promptVersion: String
}

/// 第三档 C5：模型只负责写话，这里检查它有没有越界，再用本地数值替换占位符。
/// 规则说明见仓库外一层的 `交接_建议与AI复盘.md`，改规则时两边同步。
nonisolated enum MealReviewValidator {
    nonisolated enum Rejection: Error, Hashable, Sendable {
        case unknownGuideline(String)
        case unknownReference(String)
        case unknownPlaceholder(String)
        case noReference
        case tooLong
        case bannedTerm(String)
        case rawNumber(String)
    }

    /// 占位符以外的文字最多这么多字（提示词要求 80 字，留一点余量）
    static let maxPlainTextLength = 100
    /// 不用因果词，不涉及药物、诊断、加餐和低血糖
    static let bannedTerms = ["导致", "造成", "引起", "因为", "胰岛素", "剂量", "药", "诊断", "确诊", "治疗", "治愈", "加餐", "低血糖"]
    /// "避免低血糖"是指南 G4 的原话，单独放行
    static let allowedPhrases = ["避免低血糖"]
    /// 允许直接写的数字：通用时长、指南里的 1/3、500 克、每周 5 天等；其余数字都必须用占位符
    static let allowedNumberPatterns = [
        #"(1|2|3|15|20|30|45|60|90|120)\s*个?\s*(小时|分钟)"#,
        #"1\s*[/／]\s*3"#,
        #"(500|25|5)\s*克"#,
        #"5\s*天"#,
    ]

    static func review(from draft: MealReviewDraft, payload: MealReviewPayload) -> MealReview {
        var items: [MealReview.Item] = []
        var rejectedCount = 0
        for item in draft.items {
            switch check(item, payload: payload) {
            case .success(let valid):
                items.append(valid)
            case .failure:
                rejectedCount += 1
            }
        }

        let isFallback = items.isEmpty
        if isFallback {
            items = MealReviewTemplate.items(for: payload).compactMap { try? check($0, payload: payload).get() }
        }
        return MealReview(
            items: items,
            isFallback: isFallback,
            rejectedCount: rejectedCount,
            safetyNotice: safetyNotice(for: payload),
            provider: draft.provider,
            model: draft.model,
            promptVersion: draft.promptVersion
        )
    }

    static func check(_ item: MealReviewDraftItem, payload: MealReviewPayload) -> Result<MealReview.Item, Rejection> {
        guard let guideline = DietGuideline(rawValue: item.guidelineId) else {
            return .failure(.unknownGuideline(item.guidelineId))
        }
        let knownMeals = Set(payload.meals.map(\.id))
        let knownComparisons = Set(payload.comparisons.map(\.id))
        if let unknown = item.mealIds.first(where: { !knownMeals.contains($0) })
            ?? item.comparisonIds.first(where: { !knownComparisons.contains($0) }) {
            return .failure(.unknownReference(unknown))
        }

        // 占位符：键必须在本地数据里；只在占位符里出现的餐和比较也算作引用
        let values = payload.placeholderValues
        var mealIds = item.mealIds
        var comparisonIds = item.comparisonIds
        let placeholder = placeholderRegex()
        for match in item.text.matches(of: placeholder) {
            let key = String(match.output.1)
            guard values[key] != nil else { return .failure(.unknownPlaceholder(key)) }
            let owner = String(key.prefix { $0 != "." })
            if owner.hasPrefix("M"), !mealIds.contains(owner) { mealIds.append(owner) }
            if owner.hasPrefix("C"), !comparisonIds.contains(owner) { comparisonIds.append(owner) }
        }

        let plain = item.text.replacing(placeholder, with: "")
        if let brace = plain.firstIndex(where: { $0 == "{" || $0 == "}" }) {
            return .failure(.unknownPlaceholder(String(plain[brace...].prefix(12))))
        }
        guard !mealIds.isEmpty || !comparisonIds.isEmpty else { return .failure(.noReference) }
        guard plain.count <= maxPlainTextLength else { return .failure(.tooLong) }

        var screened = plain
        for phrase in allowedPhrases {
            screened = screened.replacingOccurrences(of: phrase, with: "")
        }
        if let term = bannedTerms.first(where: { screened.contains($0) }) {
            return .failure(.bannedTerm(term))
        }

        var numbersChecked = plain
        for pattern in allowedNumberPatterns {
            numbersChecked = numbersChecked.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        if let digit = numbersChecked.firstIndex(where: { $0.isNumber && ($0.isASCII || ("０"..."９").contains($0)) }) {
            let start = numbersChecked.index(digit, offsetBy: -2, limitedBy: numbersChecked.startIndex) ?? numbersChecked.startIndex
            return .failure(.rawNumber(String(numbersChecked[start...].prefix(8))))
        }

        let rendered = item.text.replacing(placeholder) { match in values[String(match.output.1)] ?? "" }
        return .success(MealReview.Item(
            text: rendered,
            source: source(mealIds: mealIds, comparisonIds: comparisonIds, guideline: guideline, payload: payload),
            guideline: guideline,
            mealIds: mealIds,
            comparisonIds: comparisonIds
        ))
    }

    static func safetyNotice(for payload: MealReviewPayload) -> String? {
        guard payload.excludedLowMealCount > 0 else { return nil }
        return "最近有 \(payload.excludedLowMealCount) 餐的餐后时段出现低于 3.9 mmol/L 的读数，这些餐没有纳入复盘。请留意，并和医生确认你的低血糖处理方案。"
    }

    private static func source(
        mealIds: [String],
        comparisonIds: [String],
        guideline: DietGuideline,
        payload: MealReviewPayload
    ) -> String {
        var parts: [String] = []
        if mealIds.count == 1, let when = payload.placeholderValues["\(mealIds[0]).when"] {
            parts.append(when)
        } else if mealIds.count > 1 {
            parts.append("你的 \(mealIds.count) 餐记录")
        }
        parts += comparisonIds.compactMap { id in payload.comparisons.first { $0.id == id }?.title }
        parts.append("食养指南\(guideline.principleText)")
        return "依据：" + parts.joined(separator: " · ")
    }

    /// {M1.peakRise}、{C1.lunch.count} 这样的占位符；Regex 不是 Sendable，每次现建
    private static func placeholderRegex() -> Regex<(Substring, Substring)> {
        // 字面量固定，构造不会失败
        try! Regex(#"\{([A-Za-z0-9.]+)\}"#, as: (Substring, Substring).self)
    }
}
