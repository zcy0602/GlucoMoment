//
//  MealPeriod.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

nonisolated enum MealPeriod: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    /// 加餐不按时间推断，只能由用户在复核页手动选择
    case snack = "加餐"

    var id: String { rawValue }

    /// 只推断三顿正餐；加餐靠时间分不出来（下午 3 点可能是加餐，也可能是很晚的午饭）
    static func inferred(for date: Date, calendar: Calendar = .current) -> Self {
        switch calendar.component(.hour, from: date) {
        case ..<10:
            .breakfast
        case 10..<16:
            .lunch
        default:
            .dinner
        }
    }
}
