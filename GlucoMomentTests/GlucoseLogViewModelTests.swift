//
//  GlucoseLogViewModelTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@MainActor
@Suite("血糖记录按天切换")
struct GlucoseLogViewModelTests {
    private let calendar = Calendar.current
    /// 固定的「现在」：2026-11-01 01:55
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 55))!

    @Test("只列出选中那天的读数，最新的在前")
    func loadsSelectedDayNewestFirst() {
        let readings = [
            reading(2026, 10, 31, hour: 8, value: 6.1),
            reading(2026, 10, 31, hour: 20, value: 7.4),
            reading(2026, 11, 1, hour: 1, value: 5.2)
        ]
        let viewModel = makeViewModel(readings: readings)

        viewModel.load()
        #expect(viewModel.readings.map(\.value) == [5.2])

        viewModel.showPrevious()
        viewModel.load()
        #expect(viewModel.readings.map(\.value) == [7.4, 6.1])
    }

    @Test("从血糖页带过来的日期开始，带今天时跟随今天")
    func startsFromInitialDay() {
        let fromChart = makeViewModel(initialDay: day(2026, 10, 28))
        #expect(fromChart.selectedDay == day(2026, 10, 28))
        #expect(!fromChart.isShowingToday)

        let fromToday = makeViewModel(initialDay: day(2026, 11, 1))
        #expect(fromToday.isShowingToday)
    }

    @Test("往后翻到今天为止，往前最多 90 天")
    func respectsBounds() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canGoForward)

        viewModel.showNext()
        #expect(viewModel.isShowingToday)

        viewModel.select(day: day(2026, 1, 1))
        #expect(viewModel.selectedDay == viewModel.earliestDay)
        #expect(!viewModel.canGoBack)

        viewModel.showNext()
        #expect(viewModel.canGoBack)

        viewModel.showToday()
        #expect(viewModel.isShowingToday)
    }

    private func makeViewModel(readings: [GlucoseReading] = [], initialDay: Date? = nil) -> GlucoseLogViewModel {
        let fixedNow = now
        return GlucoseLogViewModel(
            repository: StubGlucoseRepository(readings: readings),
            initialDay: initialDay,
            now: { fixedNow }
        )
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func reading(_ year: Int, _ month: Int, _ day: Int, hour: Int, value: Double) -> GlucoseReading {
        GlucoseReading(
            measuredAt: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!,
            value: value
        )
    }
}

@MainActor
private final class StubGlucoseRepository: GlucoseRepository {
    private let storedReadings: [GlucoseReading]

    init(readings: [GlucoseReading]) {
        storedReadings = readings
    }

    func readings(in interval: DateInterval) throws -> [GlucoseReading] {
        storedReadings.filter { $0.measuredAt >= interval.start && $0.measuredAt < interval.end }
    }

    func latestReading() throws -> GlucoseReading? { storedReadings.last }
    func save(_ reading: GlucoseReading) async throws {}
    func delete(id: UUID) async throws {}
    func replaceHealthKitReadings(with readings: [GlucoseReading]) throws {}
}
