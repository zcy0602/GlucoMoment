//
//  GlucoseMetricsCalculatorTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@Suite("mmol/L 血糖统计")
struct GlucoseMetricsCalculatorTests {
    @Test(
        "目标范围边界正确",
        arguments: [
            (value: 3.8, expected: GlucoseState.low),
            (value: 3.9, expected: GlucoseState.inRange),
            (value: 10.0, expected: GlucoseState.inRange),
            (value: 10.1, expected: GlucoseState.elevated)
        ]
    )
    func classifiesState(value: Double, expected: GlucoseState) {
        #expect(GlucoseTargetRange.standard.state(for: value) == expected)
    }

    @Test("按实际记录计算范围占比和统计值")
    func calculatesMetrics() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let readings = [3.5, 4.0, 6.0, 11.0].map {
            GlucoseReading(measuredAt: date, value: $0)
        }

        let metrics = GlucoseMetricsCalculator.calculate(readings: readings)

        #expect(metrics.readingCount == 4)
        #expect(metrics.inRangePercentage == 50)
        #expect(metrics.average == 6.125)
        #expect(metrics.maximum == 11.0)
        #expect(metrics.minimum == 3.5)
        #expect(metrics.lowReadingCount == 1)
        #expect(metrics.highReadingCount == 1)
        #expect(metrics.belowRangePercentage == 25)
        #expect(metrics.aboveRangePercentage == 25)
    }

    @Test("三段占比取整后相加正好是 100")
    func percentagesSumToHundred() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        // 各 1/3：分别四舍五入是 33 + 33 + 33 = 99
        let readings = [3.5, 6.0, 11.0].map {
            GlucoseReading(measuredAt: date, value: $0)
        }

        let metrics = GlucoseMetricsCalculator.calculate(readings: readings)
        let total = [metrics.belowRangePercentage, metrics.inRangePercentage, metrics.aboveRangePercentage]
            .compactMap(\.self)
            .reduce(0, +)

        #expect(total == 100)
        #expect(GlucoseMetricsCalculator.roundedPercentages([1, 1, 2]) == [25, 25, 50])
        #expect(GlucoseMetricsCalculator.roundedPercentages([0, 0, 0]) == [0, 0, 0])
    }

    @Test("空数据不会伪造统计结果")
    func handlesEmptyReadings() {
        let metrics = GlucoseMetricsCalculator.calculate(readings: [])

        #expect(metrics.readingCount == 0)
        #expect(metrics.inRangePercentage == nil)
        #expect(metrics.average == nil)
        #expect(metrics.maximum == nil)
        #expect(metrics.minimum == nil)
        #expect(metrics.belowRangePercentage == nil)
        #expect(metrics.aboveRangePercentage == nil)
        #expect(metrics.lowReadingCount == 0)
    }
}
