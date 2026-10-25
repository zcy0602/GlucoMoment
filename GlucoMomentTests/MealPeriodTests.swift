//
//  MealPeriodTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

@Suite("餐次时间推断")
struct MealPeriodTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    @Test("早上 10 点前为早餐")
    func infersBreakfast() {
        #expect(MealPeriod.inferred(for: date(hour: 9, minute: 59), calendar: calendar) == .breakfast)
    }

    @Test("上午 10 点到下午 4 点前为午餐")
    func infersLunch() {
        #expect(MealPeriod.inferred(for: date(hour: 10), calendar: calendar) == .lunch)
        #expect(MealPeriod.inferred(for: date(hour: 15, minute: 59), calendar: calendar) == .lunch)
    }

    @Test("下午 4 点后为晚餐")
    func infersDinner() {
        #expect(MealPeriod.inferred(for: date(hour: 16), calendar: calendar) == .dinner)
        #expect(MealPeriod.inferred(for: date(hour: 23, minute: 59), calendar: calendar) == .dinner)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 9, hour: hour, minute: minute)
        ) ?? .distantPast
    }
}
