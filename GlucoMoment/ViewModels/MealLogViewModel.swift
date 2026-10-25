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
    let guidances: [MealPeriod: MealGuidance]
    private let repository: any MealRepository

    var currentMealPeriod: MealPeriod
    var meals: [MealRecord] = []
    var loadErrorMessage: String?

    init(
        repository: any MealRepository,
        guidances: [MealPeriod: MealGuidance]? = nil,
        referenceDate: Date = .now
    ) {
        self.repository = repository
        self.guidances = guidances ?? DemoDataProvider.mealGuidances
        currentMealPeriod = MealPeriod.inferred(for: referenceDate)
    }

    var currentGuidance: MealGuidance {
        guidances[currentMealPeriod] ?? MealGuidance(
            period: currentMealPeriod,
            title: "\(currentMealPeriod.rawValue)建议",
            text: "",
            tags: [],
            meals: []
        )
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

    var mealSections: [MealPeriodSection] {
        MealPeriod.allCases.compactMap { period in
            let periodMeals = meals.filter { $0.mealPeriod == period }
            guard !periodMeals.isEmpty else { return nil }
            return MealPeriodSection(period: period, meals: periodMeals)
        }
    }

    func reload(referenceDate: Date = .now) {
        currentMealPeriod = MealPeriod.inferred(for: referenceDate)

        guard let interval = Calendar.current.dateInterval(of: .day, for: referenceDate) else {
            meals = []
            loadErrorMessage = "无法确定今天的日期范围。"
            return
        }

        do {
            meals = try repository.meals(in: interval, period: nil)
            loadErrorMessage = nil
        } catch {
            meals = []
            loadErrorMessage = error.localizedDescription
        }
    }

    func delete(_ meal: MealRecord) async {
        do {
            try await repository.delete(id: meal.id)
            reload()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }
}
