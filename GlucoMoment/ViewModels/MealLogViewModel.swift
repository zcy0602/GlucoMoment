//
//  MealLogViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Observation

@Observable
final class MealLogViewModel {
    let title = "饮食记录"
    let mealOptions = MealPeriod.allCases
    let guidances: [MealPeriod: MealGuidance]

    var selectedMeal: MealPeriod = .lunch

    init(guidances: [MealPeriod: MealGuidance] = DemoDataProvider.mealGuidances) {
        self.guidances = guidances
    }

    var currentGuidance: MealGuidance {
        guidances[selectedMeal] ?? MealGuidance(period: selectedMeal, title: "\(selectedMeal.rawValue)建议", text: "", tags: [], meals: [])
    }

    var meals: [MealEntry] {
        currentGuidance.meals
    }

    var suggestionTitle: String {
        currentGuidance.title
    }

    var suggestionText: String {
        currentGuidance.text
    }

    var suggestionTags: [String] {
        currentGuidance.tags
    }

    func advanceSelectedMeal() {
        let currentIndex = mealOptions.firstIndex(of: selectedMeal) ?? 0
        selectedMeal = mealOptions[(currentIndex + 1) % mealOptions.count]
    }
}
