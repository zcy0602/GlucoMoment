//
//  GlucoseMetrics.swift
//  GlucoMoment
//

struct GlucoseMetrics: Equatable, Sendable {
    let readingCount: Int
    /// 低于 / 处于 / 高于目标范围的读数占比，三者相加为 100
    let inRangePercentage: Int?
    let belowRangePercentage: Int?
    let aboveRangePercentage: Int?
    let average: Double?
    let maximum: Double?
    let minimum: Double?
    let lowReadingCount: Int
    let highReadingCount: Int
}
