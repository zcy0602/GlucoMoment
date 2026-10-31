//
//  GlucoseMetricsCalculator.swift
//  GlucoMoment
//

enum GlucoseMetricsCalculator {
    static func calculate(
        readings: [GlucoseReading],
        targetRange: GlucoseTargetRange = .standard
    ) -> GlucoseMetrics {
        guard !readings.isEmpty else {
            return GlucoseMetrics(
                readingCount: 0,
                inRangePercentage: nil,
                belowRangePercentage: nil,
                aboveRangePercentage: nil,
                average: nil,
                maximum: nil,
                minimum: nil,
                lowReadingCount: 0,
                highReadingCount: 0
            )
        }

        let values = readings.map(\.value)
        let lowCount = values.count { $0 < targetRange.lowerBound }
        let highCount = values.count { $0 > targetRange.upperBound }
        let inRangeCount = values.count - lowCount - highCount
        let percentages = roundedPercentages([lowCount, inRangeCount, highCount])

        return GlucoseMetrics(
            readingCount: readings.count,
            inRangePercentage: percentages[1],
            belowRangePercentage: percentages[0],
            aboveRangePercentage: percentages[2],
            average: values.reduce(0, +) / Double(values.count),
            maximum: values.max(),
            minimum: values.min(),
            lowReadingCount: lowCount,
            highReadingCount: highCount
        )
    }

    /// 最大余数法取整：先向下取整，差的几个百分点依次补给小数部分最大的项，保证总和正好是 100
    static func roundedPercentages(_ counts: [Int]) -> [Int] {
        let total = counts.reduce(0, +)
        guard total > 0 else { return counts.map { _ in 0 } }

        let exact = counts.map { Double($0) * 100 / Double(total) }
        var result = exact.map { Int($0.rounded(.down)) }
        let remainder = 100 - result.reduce(0, +)
        let order = exact.indices.sorted {
            (exact[$0] - Double(result[$0])) > (exact[$1] - Double(result[$1]))
        }
        for index in order.prefix(remainder) {
            result[index] += 1
        }
        return result
    }
}
