//
//  TimelineEvent.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

struct TimelineEvent: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let detail: String
    let state: GlucoseState
}
