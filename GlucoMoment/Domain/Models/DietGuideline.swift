//
//  DietGuideline.swift
//  GlucoMoment
//

import Foundation

/// 稳糖建议可以引用的指南条目（白名单），原文见《成人糖尿病食养指南（2023 年版）》。
/// 识别页的建议、饮食页的提示和评分依据页都只从这里取依据；新增条目前先核对指南原文。
nonisolated enum DietGuideline: String, CaseIterable, Hashable, Sendable {
    case vegetablesEveryMeal = "G1a"
    case dairyAndSoyDaily = "G1b"
    case wholeGrainShare = "G3a"
    case vegetablesFirst = "G3b"
    case monitorResponse = "G3c"
    case activityAfterMeals = "G4"
    case lessSugarOilSalt = "G5"
    case regularMeals = "G7"

    static let sourceTitle = "成人糖尿病食养指南（2023 年版）"

    /// 指南正文的条目序号（原则一～八）
    var principle: Int {
        switch self {
        case .vegetablesEveryMeal, .dairyAndSoyDaily: 1
        case .wholeGrainShare, .vegetablesFirst, .monitorResponse: 3
        case .activityAfterMeals: 4
        case .lessSugarOilSalt: 5
        case .regularMeals: 7
        }
    }

    /// 短标题，用作标签
    var title: String {
        switch self {
        case .vegetablesEveryMeal: "餐餐有蔬菜"
        case .dairyAndSoyDaily: "天天有奶豆"
        case .wholeGrainShare: "全谷物占 1/3"
        case .vegetablesFirst: "先菜后主食"
        case .monitorResponse: "监测餐后血糖"
        case .activityAfterMeals: "餐后运动"
        case .lessSugarOilSalt: "少糖少油盐"
        case .regularMeals: "定时定量"
        }
    }

    /// 指南要点，贴近原文转述
    var summary: String {
        switch self {
        case .vegetablesEveryMeal: "餐餐都应有蔬菜，每天应达 500 克，其中深色蔬菜占一半以上。"
        case .dairyAndSoyDaily: "天天有奶类和大豆，常吃鱼、禽，适量蛋和畜肉。"
        case .wholeGrainShare: "主食定量，全谷物和杂豆类等低 GI 食物应占主食的 1/3 以上。"
        case .vegetablesFirst: "调整进餐顺序对控制血糖有利，养成先吃菜、最后吃主食的习惯。"
        case .monitorResponse: "经常监测血糖，了解身体对膳食、特别是主食的反应；记录膳食、运动和血糖。"
        case .activityAfterMeals: "餐后运动，每周至少 5 天，每次 30～45 分钟；运动前后加强血糖监测，避免低血糖。"
        case .lessSugarOilSalt: "烹调油每天 25 克以内，盐不超过 5 克，不喝含糖饮料。"
        case .regularMeals: "规律进餐，定时定量，细嚼慢咽。"
        }
    }

    var principleText: String {
        "原则\(Self.chineseNumerals[principle - 1])"
    }

    /// 不列具体条目的出处说明
    static let sourceCitation = "依据：\(sourceTitle)"

    /// 出处说明，例如「依据：成人糖尿病食养指南（2023 年版）原则三、四」；条目按原则序号排序并去重
    static func citation(for guidelines: [DietGuideline]) -> String {
        let principles = Set(guidelines.map(\.principle)).sorted()
        guard !principles.isEmpty else { return sourceCitation }
        let numerals = principles.map { chineseNumerals[$0 - 1] }.joined(separator: "、")
        return "\(sourceCitation)原则\(numerals)"
    }

    private static let chineseNumerals = ["一", "二", "三", "四", "五", "六", "七", "八"]
}
