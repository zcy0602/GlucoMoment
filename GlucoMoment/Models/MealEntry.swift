//
//  MealEntry.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

struct MealEntry: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let carbs: String
    let score: Int
    let tags: [String]
    let note: String
}
