//
//  MealPeriodSection.swift
//  GlucoMoment
//

import Foundation

struct MealPeriodSection: Identifiable {
    let period: MealPeriod
    let meals: [MealRecord]

    var id: MealPeriod { period }
}
