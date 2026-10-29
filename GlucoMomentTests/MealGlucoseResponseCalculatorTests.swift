//
//  MealGlucoseResponseCalculatorTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

/// 期望值由 `验证分析/response_fixture.py` 用 meal_response.py 对同一组合成数据算出；改算法或参数时两边同步。
@Suite("餐后血糖反应")
struct MealGlucoseResponseCalculatorTests {
    typealias Fixture = ResponseFixtures

    @Test("记录时间偏晚：起点提前到上升前的最低点，指标与 Python 原型一致")
    func earlyStart() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(recordedStart: Fixture.recorded, points: Fixture.points(Fixture.earlyStart))
        )

        #expect(response.startShiftMinutes == 18)
        Self.expectClose(response.baseline, 4.8999999999999995)
        Self.expectClose(response.peak, 10.4)
        Self.expectClose(response.peakRise, 5.500000000000001)
        Self.expectClose(response.peakMinutes, 33)
        Self.expectClose(try #require(response.rise2h), 2.0200000000000005)
        Self.expectClose(response.iAUC, 417.8700000000001)
        Self.expectCurve(response.curve, [4.9, 4.9, 4.9, 4.9, 7.4, 9.9, 9.92, 9.32, 8.72, 8.12, 7.52, 6.92, 6.32, 5.72, 5.6, 5.6])
        #expect(!response.hasLowReading)
    }

    @Test("记录时血糖平稳：按记录时间计算")
    func steadyStart() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(recordedStart: Fixture.recorded, points: Fixture.points(Fixture.steadyStart))
        )

        #expect(response.startShiftMinutes == 0)
        Self.expectClose(response.baseline, 5.8)
        Self.expectClose(response.peak, 6.3999999999999995)
        Self.expectClose(response.peakRise, 0.5999999999999996)
        Self.expectClose(response.peakMinutes, 60)
        Self.expectClose(try #require(response.rise2h), -0.39999999999999947)
        Self.expectClose(response.iAUC, 24.300000000000026)
        Self.expectCurve(response.curve, [5.8, 5.8, 5.8, 5.8, 5.8, 6.0, 6.2, 6.4, 6.15, 5.9, 5.65, 5.4, 5.15, 4.9, 4.9, 4.9])
    }

    @Test("只比记录早 6 分钟开始升：不到 10 分钟，不调整")
    func slightlyEarlyIsNotShifted() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(recordedStart: Fixture.recorded, points: Fixture.points(Fixture.slightlyEarly))
        )

        #expect(response.startShiftMinutes == 0)
        Self.expectClose(response.baseline, 5.2)
        Self.expectClose(response.peakRise, 4.6000000000000005)
        Self.expectClose(response.peakMinutes, 30)
        Self.expectClose(response.iAUC, 492.0000000000003)
    }

    @Test("只有几条指尖血：窗口内数据不足，不计算")
    func sparseReadingsAreSkipped() {
        let points = [-30, 0, 120].map {
            GlucosePoint(time: Fixture.recorded.addingTimeInterval(Double($0) * 60), value: 6)
        }
        #expect(MealGlucoseResponseCalculator.response(recordedStart: Fixture.recorded, points: points) == nil)
    }

    @Test("餐前 45 分钟到餐后 180 分钟内有低于 3.9 的读数时标记出来")
    func flagsLowReadings() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(recordedStart: Fixture.recorded, points: Fixture.points(Fixture.lowAfterMeal))
        )
        #expect(response.hasLowReading)
    }

    @Test("读数顺序打乱也能正确计算")
    func sortsPoints() throws {
        let shuffled = Fixture.points(Fixture.earlyStart).reversed()
        let response = try #require(
            MealGlucoseResponseCalculator.response(recordedStart: Fixture.recorded, points: Array(shuffled))
        )
        #expect(response.startShiftMinutes == 18)
    }

    @Test("两餐相隔 60 分钟：不传下一餐时会取到下一餐的峰")
    func secondMealPeakWithoutNeighbor() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(recordedStart: Fixture.recorded, points: Fixture.points(Fixture.twoMeals))
        )
        Self.expectClose(response.peakRise, 4.0)
        Self.expectClose(response.peakMinutes, 105)
        #expect(response.cutOffMinutes == nil)
    }

    @Test("两餐相隔 60 分钟、下一餐前已回落：两个峰，窗口截到下一餐开始，只取前一个峰")
    func cutsWindowAtNextMeal() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(
                recordedStart: Fixture.recorded,
                points: Fixture.points(Fixture.twoMeals),
                nextMealStart: Fixture.recorded.addingTimeInterval(60 * 60)
            )
        )
        Self.expectClose(response.baseline, 5.0)
        Self.expectClose(response.peak, 7.0)
        Self.expectClose(response.peakRise, 2.0)
        Self.expectClose(response.peakMinutes, 30)
        #expect(response.rise2h == nil)
        Self.expectClose(response.iAUC, 75.00000000000001)
        Self.expectClose(try #require(response.cutOffMinutes), 60)
        #expect(!response.sharesPeakWithAdjacentMeal)
    }

    @Test("下一餐在 2 小时以后：不截断")
    func ignoresLaterNextMeal() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(
                recordedStart: Fixture.recorded,
                points: Fixture.points(Fixture.steadyStart),
                nextMealStart: Fixture.recorded.addingTimeInterval(150 * 60)
            )
        )
        #expect(response.cutOffMinutes == nil)
        #expect(response.rise2h != nil)
    }

    @Test("下一餐在第 20 分钟、血糖还在同一个峰上：当作连着吃，算到这个峰回落为止")
    func sharesPeakWithNextMeal() throws {
        let response = try #require(
            MealGlucoseResponseCalculator.response(
                recordedStart: Fixture.recorded,
                points: Fixture.points(Fixture.oneLongPeak),
                nextMealStart: Fixture.recorded.addingTimeInterval(20 * 60)
            )
        )
        Self.expectClose(response.baseline, 5.0)
        Self.expectClose(response.peak, 6.6)
        Self.expectClose(response.peakRise, 1.5999999999999996)
        Self.expectClose(response.peakMinutes, 48)
        #expect(response.rise2h == nil)
        Self.expectClose(response.iAUC, 78.89999999999999)
        #expect(response.cutOffMinutes == nil)
        #expect(response.sharesPeakWithAdjacentMeal)
    }

    @Test("上一餐在 1 小时内、开始时血糖已在升：不提前开始时间，标为连着吃")
    func previousMealBlocksOnsetShift() throws {
        let points = Fixture.points(Fixture.earlyStart)
        let recent = try #require(
            MealGlucoseResponseCalculator.response(
                recordedStart: Fixture.recorded,
                points: points,
                previousMealStart: Fixture.recorded.addingTimeInterval(-30 * 60)
            )
        )
        #expect(recent.startShiftMinutes == 0)
        Self.expectClose(recent.baseline, 6.6499999999999995)
        Self.expectClose(recent.peakRise, 3.750000000000001)
        Self.expectClose(recent.peakMinutes, 15)
        Self.expectClose(recent.iAUC, 213.28125000000009)
        #expect(recent.sharesPeakWithAdjacentMeal)

        let earlier = try #require(
            MealGlucoseResponseCalculator.response(
                recordedStart: Fixture.recorded,
                points: points,
                previousMealStart: Fixture.recorded.addingTimeInterval(-90 * 60)
            )
        )
        #expect(earlier.startShiftMinutes == 18)
        #expect(!earlier.sharesPeakWithAdjacentMeal)
    }

    @Test("前后相邻的餐：取最近的前一餐和后一餐，时间相同的不算")
    func findsAdjacentMeals() {
        let t = Fixture.recorded
        let starts = [-180, -40, 0, 0, 50, 200].map { t.addingTimeInterval(Double($0) * 60) }
        let adjacent = MealGlucoseResponseCalculator.adjacentMealStarts(of: t, among: starts)
        #expect(adjacent.previous == t.addingTimeInterval(-40 * 60))
        #expect(adjacent.next == t.addingTimeInterval(50 * 60))
        let alone = MealGlucoseResponseCalculator.adjacentMealStarts(of: t, among: [t])
        #expect(alone.previous == nil && alone.next == nil)
    }

    private static func expectClose(_ actual: Double, _ expected: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual - expected) < 1e-9, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
    }

    private static func expectCurve(_ actual: [Double?], _ expected: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        for (value, target) in zip(actual, expected) {
            #expect(value.map { abs($0 - target) < 1e-6 } == true, "\(String(describing: value)) ≠ \(target)", sourceLocation: sourceLocation)
        }
    }
}

/// 与 `验证分析/response_fixture.py` 相同的合成数据：每 3 分钟一条，从记录时间前 90 分钟到后 240 分钟
enum ResponseFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }()

    /// 2026-10-21（周三）20:00
    static let recorded = date(month: 10, day: 21, hour: 20)

    static func date(month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .distantPast
    }

    static func points(_ shape: (Int) -> Double, around recorded: Date = recorded) -> [GlucosePoint] {
        stride(from: -90, through: 240, by: 3).map { minute in
            GlucosePoint(time: recorded.addingTimeInterval(Double(minute) * 60), value: shape(minute))
        }
    }

    /// 实际比记录早 18 分钟开始吃：平稳 4.9 → 每 3 分钟升 0.5 → 每 3 分钟降 0.12 → 平稳 5.6
    static func earlyStart(_ minute: Int) -> Double {
        if minute <= -18 { return 4.9 }
        if minute <= 15 { return 4.9 + Double(minute + 18) / 3 * 0.5 }
        if minute <= 135 { return 10.4 - Double(minute - 15) / 3 * 0.12 }
        return 5.6
    }

    /// 记录时血糖平稳：5.8 → 每 3 分钟升 0.04 → 每 3 分钟降 0.05 → 4.9
    static func steadyStart(_ minute: Int) -> Double {
        if minute <= 15 { return 5.8 }
        if minute <= 60 { return 5.8 + Double(minute - 15) / 3 * 0.04 }
        if minute <= 150 { return 6.4 - Double(minute - 60) / 3 * 0.05 }
        return 4.9
    }

    /// 只比记录早 6 分钟开始升
    static func slightlyEarly(_ minute: Int) -> Double {
        if minute <= -6 { return 5.0 }
        if minute <= 30 { return 5.0 + Double(minute + 6) / 3 * 0.4 }
        return 9.8
    }

    /// 第 60 分钟又吃了一餐：5.0 → 第 30 分钟 7.0 → 第 60 分钟回落到 6.0 → 第 105 分钟 9.0 → 缓慢回落
    static func twoMeals(_ minute: Int) -> Double {
        if minute <= 0 { return 5.0 }
        if minute <= 30 { return 5.0 + Double(minute) / 3 * 0.2 }
        if minute <= 60 { return 7.0 - Double(minute - 30) / 3 * 0.1 }
        if minute <= 105 { return 6.0 + Double(minute - 60) / 3 * 0.2 }
        if minute <= 180 { return 9.0 - Double(minute - 105) / 3 * 0.07 }
        return 7.25
    }

    /// 连着吃、只有一个峰：5.0 → 第 48 分钟 6.6 → 每 3 分钟降 0.05 → 4.9
    static func oneLongPeak(_ minute: Int) -> Double {
        if minute <= 0 { return 5.0 }
        if minute <= 48 { return 5.0 + Double(minute) / 3 * 0.1 }
        if minute <= 150 { return 6.6 - Double(minute - 48) / 3 * 0.05 }
        return 4.9
    }

    /// 与 steadyStart 相同，但餐后 150～171 分钟降到 3.6
    static func lowAfterMeal(_ minute: Int) -> Double {
        (150...171).contains(minute) ? 3.6 : steadyStart(minute)
    }
}
