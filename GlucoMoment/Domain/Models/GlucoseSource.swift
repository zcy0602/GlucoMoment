//
//  GlucoseSource.swift
//  GlucoMoment
//

enum GlucoseSource: String, Codable, CaseIterable, Sendable {
    case manual
    case healthKit

    var label: String {
        switch self {
        case .manual:
            "手动记录"
        case .healthKit:
            "健康 App"
        }
    }
}
