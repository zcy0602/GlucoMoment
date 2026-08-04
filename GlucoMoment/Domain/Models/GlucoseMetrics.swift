//
//  GlucoseMetrics.swift
//  GlucoMoment
//

struct GlucoseMetrics: Equatable, Sendable {
    let readingCount: Int
    let inRangePercentage: Int?
    let average: Double?
    let maximum: Double?
    let lowReadingCount: Int
}
