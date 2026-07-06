//
//  MealPeriod.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

enum MealPeriod: String, CaseIterable, Hashable, Identifiable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"

    var id: String { rawValue }
}
