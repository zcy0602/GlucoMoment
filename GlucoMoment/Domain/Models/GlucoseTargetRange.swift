//
//  GlucoseTargetRange.swift
//  GlucoMoment
//

struct GlucoseTargetRange: Hashable, Sendable {
    static let standard = GlucoseTargetRange(lowerBound: 3.9, upperBound: 10.0)

    let lowerBound: Double
    let upperBound: Double

    func state(for value: Double) -> GlucoseState {
        if value < lowerBound {
            .low
        } else if value > upperBound {
            .elevated
        } else {
            .inRange
        }
    }

    func contains(_ value: Double) -> Bool {
        lowerBound...upperBound ~= value
    }
}
