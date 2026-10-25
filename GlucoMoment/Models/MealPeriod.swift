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

    var id: String { rawValue }

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
