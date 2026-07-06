//
//  TrendRange.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

enum TrendRange: String, CaseIterable, Hashable, Identifiable {
    case today = "今日"
    case week = "7天"
    case month = "30天"

    var id: String { rawValue }
}
