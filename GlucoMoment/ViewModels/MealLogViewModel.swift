//
//  MealLogViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation
import Observation

@MainActor
@Observable
final class MealLogViewModel {
    let title = "饮食记录"
    let mealOptions = MealPeriod.allCases
    let guidances: [MealPeriod: MealGuidance]
    private let repository: any MealRepository

    var selectedMeal: MealPeriod = .lunch
    var meals: [MealRecord] = []
    var loadErrorMessage: String?

    init(
        repository: any MealRepository,
        guidances: [MealPeriod: MealGuidance]? = nil
    ) {
        self.repository = repository
        self.guidances = guidances ?? DemoDataProvider.mealGuidances
    }

    var currentGuidance: MealGuidance {
        guidances[selectedMeal] ?? MealGuidance(period: selectedMeal, title: "\(selectedMeal.rawValue)建议", text: "", tags: [], meals: [])
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

    func reload(referenceDate: Date = .now) {
        guard let interval = Calendar.current.dateInterval(of: .day, for: referenceDate) else {
            meals = []
            loadErrorMessage = "无法确定今天的日期范围。"
            return
        }

        do {
            meals = try repository.meals(in: interval, period: selectedMeal)
            loadErrorMessage = nil
        } catch {
            meals = []
            loadErrorMessage = error.localizedDescription
        }
    }

    func delete(_ meal: MealRecord) {
        do {
            try repository.delete(id: meal.id)
            reload()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }
}
