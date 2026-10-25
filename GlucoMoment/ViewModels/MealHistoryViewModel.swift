//
//  MealHistoryViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

@MainActor
@Observable
final class MealHistoryViewModel {
    private let repository: any MealRepository

    var selectedDate: Date
    private(set) var meals: [MealRecord] = []
    private(set) var errorMessage: String?

    init(repository: any MealRepository, initialDate: Date? = nil) {
        self.repository = repository
        selectedDate = initialDate ?? Self.defaultHistoryDate
    }

    var recordSubtitle: String {
        if meals.isEmpty {
            "当天暂无记录"
        } else {
            "当天共 \(meals.count) 条记录"
        }
    }

    var mealSections: [MealPeriodSection] {
        MealPeriod.allCases.compactMap { period in
            let periodMeals = meals.filter { $0.mealPeriod == period }
            guard !periodMeals.isEmpty else { return nil }
            return MealPeriodSection(period: period, meals: periodMeals)
        }
    }

    func load() {
        guard let interval = Calendar.current.dateInterval(of: .day, for: selectedDate) else {
            meals = []
            errorMessage = "无法确定所选日期的时间范围。"
            return
        }

        do {
            meals = try repository.meals(in: interval, period: nil)
            errorMessage = nil
        } catch {
            meals = []
            errorMessage = "读取历史饮食失败：\(error.localizedDescription)"
        }
    }

    private static var defaultHistoryDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    }
}
