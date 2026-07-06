//
//  FoodRecognitionResult.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/7/6.
//

import Foundation

struct FoodRecognitionResult {
    let name: String
    let confidence: String
    let calories: String
    let carbs: String
    let protein: String
    let fat: String
    let glucoseImpact: String
    let score: Int
    let ingredients: [String]
    let suggestions: [String]
}
