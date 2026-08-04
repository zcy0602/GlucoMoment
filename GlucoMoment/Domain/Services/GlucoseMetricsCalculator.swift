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
                average: nil,
                maximum: nil,
                lowReadingCount: 0
            )
        }

        let values = readings.map(\.value)
        let inRangeCount = values.count(where: targetRange.contains)

        return GlucoseMetrics(
            readingCount: readings.count,
            inRangePercentage: Int((Double(inRangeCount) / Double(readings.count) * 100).rounded()),
            average: values.reduce(0, +) / Double(values.count),
            maximum: values.max(),
            lowReadingCount: values.count { $0 < targetRange.lowerBound }
        )
    }
}
