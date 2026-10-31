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

    /// 新版血糖页分段控件的文字。可以往前翻页，所以不写「今日」
    var shortTitle: String {
        switch self {
        case .today: "日"
        case .week: "周"
        case .month: "月"
        }
    }
}
