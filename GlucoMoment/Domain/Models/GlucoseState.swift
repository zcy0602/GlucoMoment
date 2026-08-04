//
//  GlucoseState.swift
//  GlucoMoment
//

enum GlucoseState: String, Codable, Sendable {
    case low
    case inRange
    case elevated

    var label: String {
        switch self {
        case .low:
            "偏低"
        case .inRange:
            "目标范围"
        case .elevated:
            "偏高"
        }
    }
}
