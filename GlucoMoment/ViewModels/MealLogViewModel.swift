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
    /// 最近一次加载的时间；晚于它的记录不参与下一餐提示
    private(set) var referenceDate: Date

    init(
        repository: any MealRepository,
        guidances: [MealPeriod: MealGuidance]? = nil,
        referenceDate: Date = .now
    ) {
        self.repository = repository
        self.guidances = guidances ?? DemoDataProvider.mealGuidances
        self.referenceDate = referenceDate
        currentMealPeriod = MealPeriod.inferred(for: referenceDate)
    }

    var currentGuidance: MealGuidance {
        guidances[currentMealPeriod] ?? MealGuidance(
            period: currentMealPeriod,
            title: "\(currentMealPeriod.rawValue)建议",
            text: "",
            tags: [],
            guidelines: []
        )
    }

    /// 根据今天已记录的餐给出的下一餐提示；没有触发规则时为 nil，显示当前餐次的通用建议
    var nextMealSuggestion: MealSuggestion? {
        MealSuggestionEngine.nextMealSuggestion(
            basedOn: meals.filter { $0.eatenAt <= referenceDate }
        )
    }

    var suggestionTitle: String {
        nextMealSuggestion == nil ? currentGuidance.title : "下一餐提示"
    }

    var suggestionText: String {
        nextMealSuggestion?.text ?? currentGuidance.text
    }

    var suggestionTags: [String] {
        nextMealSuggestion.map { [$0.guideline.title] } ?? currentGuidance.tags
    }

    var suggestionCitation: String {
        DietGuideline.citation(
            for: nextMealSuggestion.map { [$0.guideline] } ?? currentGuidance.guidelines
        )
    }

    var mealSections: [MealPeriodSection] {
        MealPeriod.allCases.compactMap { period in
            let periodMeals = meals.filter { $0.mealPeriod == period }
            guard !periodMeals.isEmpty else { return nil }
            return MealPeriodSection(period: period, meals: periodMeals)
        }
    }

    func reload(referenceDate: Date = .now) {
        self.referenceDate = referenceDate
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
