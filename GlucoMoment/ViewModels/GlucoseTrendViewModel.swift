//
//  GlucoseTrendViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Observation
import SwiftUI

@Observable
final class GlucoseTrendViewModel {
    let title = "血糖趋势"
    let rangeOptions = TrendRange.allCases

    var selectedRange: TrendRange = .today

    var readings: [GlucoseReading] {
        switch selectedRange {
        case .today:
            DemoDataProvider.readings
        case .week:
            DemoDataProvider.weeklyReadings
        case .month:
            DemoDataProvider.monthlyReadings
        }
    }

    var metrics: [DashboardMetric] {
        switch selectedRange {
        case .today:
            [
                DashboardMetric(title: "范围内时间", value: "84%", caption: "+6% 较昨日", systemImage: "target", tint: Color.brandLeaf),
                DashboardMetric(title: "平均血糖", value: "118", caption: "mg/dL", systemImage: "number", tint: Color.brandTeal),
                DashboardMetric(title: "最高峰值", value: "152", caption: "午餐后", systemImage: "arrow.up.right", tint: Color.brandAmber),
                DashboardMetric(title: "低血糖次数", value: "0", caption: "近 24 小时", systemImage: "shield.checkered", tint: Color.brandLeaf)
            ]
        case .week:
            [
                DashboardMetric(title: "范围内时间", value: "81%", caption: "-2% 较上周", systemImage: "target", tint: Color.brandAmber),
                DashboardMetric(title: "平均血糖", value: "131", caption: "mg/dL", systemImage: "number", tint: Color.brandTeal),
                DashboardMetric(title: "最高峰值", value: "158", caption: "周四午餐后", systemImage: "arrow.up.right", tint: Color.brandAmber),
                DashboardMetric(title: "记录天数", value: "7/7", caption: "本周完整", systemImage: "calendar.badge.checkmark", tint: Color.brandLeaf)
            ]
        case .month:
            [
                DashboardMetric(title: "范围内时间", value: "86%", caption: "+8% 较月初", systemImage: "target", tint: Color.brandLeaf),
                DashboardMetric(title: "平均血糖", value: "130", caption: "mg/dL", systemImage: "number", tint: Color.brandTeal),
                DashboardMetric(title: "最高峰值", value: "151", caption: "10 日外食后", systemImage: "arrow.up.right", tint: Color.brandAmber),
                DashboardMetric(title: "稳定趋势", value: "改善", caption: "后半月波动降低", systemImage: "chart.line.downtrend.xyaxis", tint: Color.brandLeaf)
            ]
        }
    }

    var insights: [Insight] {
        switch selectedRange {
        case .today:
            DemoDataProvider.insights
        case .week:
            DemoDataProvider.weeklyInsights
        case .month:
            DemoDataProvider.monthlyInsights
        }
    }

    var trendTitle: String {
        "\(selectedRange.rawValue)曲线"
    }

    var statusLabel: String {
        switch selectedRange {
        case .today:
            "平稳"
        case .week:
            "有波动"
        case .month:
            "改善中"
        }
    }

    var statusTint: Color {
        switch selectedRange {
        case .today, .month:
            Color.brandLeaf
        case .week:
            Color.brandAmber
        }
    }

    func chartPoints(in size: CGSize) -> [CGPoint] {
        let minValue: CGFloat = 70
        let maxValue: CGFloat = 180
        let widthStep = size.width / CGFloat(max(readings.count - 1, 1))

        return readings.enumerated().map { index, reading in
            let normalized = (CGFloat(reading.value) - minValue) / (maxValue - minValue)
            let y = size.height - (normalized * size.height)
            return CGPoint(x: CGFloat(index) * widthStep, y: min(max(y, 8), size.height - 8))
        }
    }
}
