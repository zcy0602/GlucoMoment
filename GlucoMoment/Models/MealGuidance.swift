//
//  MealGuidance.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

struct MealGuidance {
    let period: MealPeriod
    let title: String
    let text: String
    let tags: [String]
    let meals: [MealEntry]
}
