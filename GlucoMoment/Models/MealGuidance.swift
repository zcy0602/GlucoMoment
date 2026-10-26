//
//  MealGuidance.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

/// 饮食页按餐次显示的通用建议；文案须能在 `guidelines` 对应的指南条目中找到依据
struct MealGuidance {
    let period: MealPeriod
    let title: String
    let text: String
    let tags: [String]
    let guidelines: [DietGuideline]
}
