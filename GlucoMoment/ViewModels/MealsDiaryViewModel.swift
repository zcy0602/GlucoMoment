//
//  MealsDiaryViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 新版饮食页：顶部日期条可以回看最近 30 天，下面是所选那天按餐次分组的记录。
/// 一次读出 30 天的餐，切换日期只在本地筛选
@MainActor
@Observable
final class MealsDiaryViewModel {
    static let visibleDayCount = 30

    private let repository: any MealRepository
    private let calendar: Calendar

    var selectedDate: Date
    private(set) var today: Date
    private(set) var recentMeals: [MealRecord] = []
    private(set) var errorMessage: String?

    init(repository: any MealRepository, now: Date = .now, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        selectedDate = calendar.startOfDay(for: now)
    }

    /// 日期条显示的日期，从 29 天前到今天
    var days: [Date] {
        (0..<Self.visibleDayCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    var meals: [MealRecord] {
        recentMeals.filter { calendar.isDate($0.eatenAt, inSameDayAs: selectedDate) }
    }

    var sections: [MealPeriodSection] {
        let meals = meals
        return MealPeriod.allCases.compactMap { period in
            let periodMeals = meals.filter { $0.mealPeriod == period }
            return periodMeals.isEmpty ? nil : MealPeriodSection(period: period, meals: periodMeals)
        }
    }

    func hasMeals(on day: Date) -> Bool {
        recentMeals.contains { calendar.isDate($0.eatenAt, inSameDayAs: day) }
    }

    var isSelectedToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: today)
    }

    var totalCalories: Double {
        meals.reduce(0) { $0 + $1.caloriesKcal }
    }

    var totalCarbohydrates: Double {
        meals.reduce(0) { $0 + $1.carbohydratesGrams }
    }

    /// 有分数的餐的平均稳糖分；一餐都没有分数时为 nil
    var averageScore: Int? {
        let scores = meals.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    func load(now: Date = .now) {
        today = calendar.startOfDay(for: now)
        if selectedDate > today {
            selectedDate = today
        }
        guard let start = calendar.date(byAdding: .day, value: -(Self.visibleDayCount - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else {
            recentMeals = []
            errorMessage = "无法确定日期范围。"
            return
        }

        do {
            recentMeals = try repository.meals(in: DateInterval(start: start, end: end), period: nil)
            errorMessage = nil
        } catch {
            recentMeals = []
            errorMessage = "读取饮食记录失败：\(error.localizedDescription)"
        }
    }

    func select(_ day: Date) {
        selectedDate = calendar.startOfDay(for: day)
    }

    func delete(_ meal: MealRecord) async {
        do {
            try await repository.delete(id: meal.id)
            load()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}
