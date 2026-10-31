//
//  GlucoseTrendViewModelTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@MainActor
@Suite("血糖页时间段切换")
struct GlucoseTrendViewModelTests {
    private let calendar = Calendar.current
    /// 固定的「现在」：2026-11-01 01:55
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 55))!

    @Test("默认看今天，周和月截止到今天")
    func defaultsToToday() {
        let viewModel = makeViewModel()

        #expect(viewModel.isShowingToday)
        #expect(!viewModel.canGoForward)
        #expect(viewModel.interval == DateInterval(start: day(2026, 11, 1), end: day(2026, 11, 2)))

        viewModel.selectedRange = .week
        #expect(viewModel.interval == DateInterval(start: day(2026, 10, 26), end: day(2026, 11, 2)))

        viewModel.selectedRange = .month
        #expect(viewModel.interval == DateInterval(start: day(2026, 10, 3), end: day(2026, 11, 2)))
    }

    @Test("往前翻一整段，往后翻回到今天")
    func pagesByWholePeriod() {
        let viewModel = makeViewModel()
        viewModel.selectedRange = .week

        viewModel.showPrevious()
        #expect(!viewModel.isShowingToday)
        #expect(viewModel.interval == DateInterval(start: day(2026, 10, 19), end: day(2026, 10, 26)))

        viewModel.showNext()
        #expect(viewModel.isShowingToday)
        #expect(viewModel.anchorDay == nil)
    }

    @Test("最多往前翻 90 天")
    func stopsAtLookbackLimit() {
        let viewModel = makeViewModel()
        viewModel.selectedRange = .month

        viewModel.showPrevious()
        viewModel.showPrevious()
        viewModel.showPrevious()
        #expect(viewModel.endDay == day(2026, 8, 3))
        #expect(!viewModel.canGoBack)

        viewModel.showPrevious()
        #expect(viewModel.endDay == day(2026, 8, 3))
    }

    @Test("选日期时截到可选范围内，选今天回到跟随今天")
    func clampsSelectedDay() {
        let viewModel = makeViewModel()

        viewModel.select(endDay: day(2026, 1, 1))
        #expect(viewModel.endDay == viewModel.earliestEndDay)

        viewModel.select(endDay: day(2026, 12, 25))
        #expect(viewModel.isShowingToday)

        viewModel.select(endDay: day(2026, 10, 31).addingTimeInterval(15 * 3_600))
        #expect(viewModel.endDay == day(2026, 10, 31))

        viewModel.showToday()
        #expect(viewModel.isShowingToday)
    }

    @Test("只读取选中时间段内的读数")
    func loadsReadingsInInterval() {
        let readings = [
            GlucoseReading(measuredAt: day(2026, 10, 30).addingTimeInterval(8 * 3_600), value: 6.1),
            GlucoseReading(measuredAt: day(2026, 10, 31).addingTimeInterval(8 * 3_600), value: 7.2),
            GlucoseReading(measuredAt: day(2026, 11, 1).addingTimeInterval(3_600), value: 5.4)
        ]
        let viewModel = makeViewModel(readings: readings)

        viewModel.select(endDay: day(2026, 10, 31))
        viewModel.load()

        #expect(viewModel.readings.map(\.value) == [7.2])
    }

    private func makeViewModel(readings: [GlucoseReading] = []) -> GlucoseTrendViewModel {
        let fixedNow = now
        return GlucoseTrendViewModel(repository: StubGlucoseRepository(readings: readings), now: { fixedNow })
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
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
