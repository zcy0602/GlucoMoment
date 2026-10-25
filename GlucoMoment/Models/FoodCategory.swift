//
//  FoodCategory.swift
//  GlucoMoment
//

import Foundation

/// 按碳水主要来源划分的食物类别，用于查 GI 计算 GL。
/// 原始值须与代理 `Backend/FoodAnalysisProxy/src/core.ts` 的 `FOOD_CATEGORIES` 一致。
nonisolated enum FoodCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case refinedGrain = "精制谷物"
    case wholeGrainLegume = "全谷杂豆"
    case tuber = "薯类"
    case addedSugar = "添加糖"
    case fruit = "水果"
    case dairy = "乳制品"
    case vegetable = "蔬菜"
    case protein = "肉蛋鱼豆"
    case nutFat = "坚果油脂"
    case other = "其他"

    /// 模型返回值不在列表中时归为「其他」；未返回时为 nil（旧版代理或其他服务商）。
    init?(modelValue: String?) {
        guard let trimmed = modelValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        self = FoodCategory(rawValue: trimmed) ?? .other
    }
}
