//
//  DashboardMetric.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation
import SwiftUI

struct DashboardMetric: Identifiable {
    var id: String { title }

    let title: String
    let value: String
    let caption: String
    let systemImage: String
    let tint: Color
}

struct CurrentGlucoseSnapshot {
    let value: String
    let unit: String
    let stateLabel: String
    let stateTint: Color
    let measuredAt: Date
}
