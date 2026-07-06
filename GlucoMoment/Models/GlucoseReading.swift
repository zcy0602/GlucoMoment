//
//  GlucoseReading.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

struct GlucoseReading: Identifiable {
    let id = UUID()
    let hour: String
    let value: Int
    let state: GlucoseState
}

enum GlucoseState {
    case low
    case inRange
    case elevated

    var label: String {
        switch self {
        case .low:
            "偏低"
        case .inRange:
            "平稳"
        case .elevated:
            "偏高"
        }
    }
}
