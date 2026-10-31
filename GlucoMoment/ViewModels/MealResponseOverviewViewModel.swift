//
//  MealResponseOverviewViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 「复盘」页：最近 14 天每一餐的稳糖分和实测餐后反应。
/// 没有连续血糖数据的餐也列出来（只显示稳糖分），对照图只用两者都有的餐
@MainActor
@Observable
final class MealResponseOverviewViewModel {
    enum SortOrder: String, CaseIterable, Identifiable {
        case recent = "最近"
        case highestRise = "升得最多"
        case flattest = "最平稳"

        var id: Self { self }
    }

    struct Entry: Identifiable {
        let meal: MealRecord
        /// 这一餐前后连续血糖不足时为 nil
        let response: MealGlucoseResponse?

        var id: UUID { meal.id }
    }

    /// 与 AI 复盘统计的天数一致
    static let reviewDays = MealReviewPayloadBuilder.reviewDays
    /// 计算单餐反应时取用餐前后多长时间的血糖：起点最多往前调 60 分钟，曲线再往前 45 分钟，往后到 180 分钟
    private static let lookbackSeconds: TimeInterval = 2 * 60 * 60
    private static let lookaheadSeconds: TimeInterval = 4 * 60 * 60

    private let glucoseRepository: any GlucoseRepository
    private let mealRepository: any MealRepository
    private let now: () -> Date

    private(set) var entries: [Entry] = []
    private(set) var errorMessage: String?
    var sortOrder: SortOrder = .recent

    init(
        glucoseRepository: any GlucoseRepository,
        mealRepository: any MealRepository,
        now: @escaping () -> Date = { .now }
    ) {
        self.glucoseRepository = glucoseRepository
        self.mealRepository = mealRepository
        self.now = now
    }

    /// 有完整餐后血糖的餐
    var respondedEntries: [Entry] {
        entries.filter { $0.response != nil }
    }

    /// 对照图的点：既有稳糖分又有餐后升幅
    var comparisonEntries: [Entry] {
        respondedEntries.filter { $0.meal.score != nil }
    }

    var averagePeakRise: Double? {
        let rises = respondedEntries.compactMap { $0.response?.peakRise }
        guard !rises.isEmpty else { return nil }
        return rises.reduce(0, +) / Double(rises.count)
    }

    var averageScore: Int? {
        let scores = entries.compactMap(\.meal.score)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    /// 按升幅排序时，没有餐后血糖的餐排在最后，彼此之间按时间从新到旧
    var sortedEntries: [Entry] {
        let recent = entries.sorted { $0.meal.eatenAt > $1.meal.eatenAt }
        switch sortOrder {
        case .recent:
            return recent
        case .highestRise:
            return recent.filter { $0.response != nil }.sorted { rise($0) > rise($1) }
                + recent.filter { $0.response == nil }
        case .flattest:
            return recent.filter { $0.response != nil }.sorted { rise($0) < rise($1) }
                + recent.filter { $0.response == nil }
        }
    }

    func load() {
        let end = now()
        let interval = DateInterval(
            start: end.addingTimeInterval(-Double(Self.reviewDays) * 86_400),
            end: end
        )
        do {
            let meals = try mealRepository.meals(in: interval, period: nil)
            let readingInterval = DateInterval(
                start: interval.start.addingTimeInterval(-Self.lookbackSeconds),
                end: end
            )
            let points = try glucoseRepository.readings(in: readingInterval)
                .map { GlucosePoint(time: $0.measuredAt, value: $0.value) }
                .sorted { $0.time < $1.time }

            let starts = meals.map(\.eatenAt)
            entries = meals.map { meal in
                let window = points.filter {
                    $0.time >= meal.eatenAt.addingTimeInterval(-Self.lookbackSeconds)
                        && $0.time <= meal.eatenAt.addingTimeInterval(Self.lookaheadSeconds)
                }
                let adjacent = MealGlucoseResponseCalculator.adjacentMealStarts(of: meal.eatenAt, among: starts)
                return Entry(
                    meal: meal,
                    response: MealGlucoseResponseCalculator.response(
                        recordedStart: meal.eatenAt,
                        points: window,
                        previousMealStart: adjacent.previous,
                        nextMealStart: adjacent.next
                    )
                )
            }
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = "读取记录失败：\(error.localizedDescription)"
        }
    }

    private func rise(_ entry: Entry) -> Double {
        entry.response?.peakRise ?? 0
    }
}
