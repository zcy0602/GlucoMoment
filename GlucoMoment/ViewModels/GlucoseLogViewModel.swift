//
//  GlucoseLogViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 新版「血糖记录」：一次看一天，最新的在前。CGM 一天有上百条读数，按天翻页比一次列出 30 天好找。
/// 可往前翻的天数与血糖页一致
@MainActor
@Observable
final class GlucoseLogViewModel {
    static let maxLookbackDays = GlucoseTrendViewModel.maxLookbackDays

    private let repository: any GlucoseRepository
    private let calendar: Calendar
    private let now: () -> Date

    /// 正在看的那天（0 点）。nil 表示跟随今天，过了午夜会自动换到新的一天
    private(set) var anchorDay: Date?
    private(set) var readings: [GlucoseReading] = []
    private(set) var errorMessage: String?

    /// `initialDay` 为 nil 时从今天开始
    init(
        repository: any GlucoseRepository,
        initialDay: Date? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
        if let initialDay {
            select(day: initialDay)
        }
    }

    // MARK: 日期

    var today: Date { calendar.startOfDay(for: now()) }

    var selectedDay: Date { anchorDay ?? today }

    var isShowingToday: Bool { anchorDay == nil }

    var earliestDay: Date {
        calendar.date(byAdding: .day, value: -Self.maxLookbackDays, to: today) ?? today
    }

    var canGoBack: Bool { selectedDay > earliestDay }

    var canGoForward: Bool { !isShowingToday }

    func showPrevious() {
        guard canGoBack, let previous = calendar.date(byAdding: .day, value: -1, to: selectedDay) else { return }
        select(day: previous)
    }

    func showNext() {
        guard canGoForward, let next = calendar.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        select(day: next)
    }

    func showToday() {
        anchorDay = nil
    }

    /// 选定某一天，超出可选范围时取最近的边界
    func select(day date: Date) {
        let day = min(max(calendar.startOfDay(for: date), earliestDay), today)
        anchorDay = day == today ? nil : day
    }

    // MARK: 读写

    func load() {
        guard let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) else {
            readings = []
            return
        }

        do {
            readings = try repository.readings(in: DateInterval(start: selectedDay, end: end))
                .sorted { $0.measuredAt > $1.measuredAt }
            errorMessage = nil
        } catch {
            readings = []
            errorMessage = "读取血糖记录失败：\(error.localizedDescription)"
        }
    }

    func delete(_ reading: GlucoseReading) async {
        do {
            try await repository.delete(id: reading.id)
            load()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}
