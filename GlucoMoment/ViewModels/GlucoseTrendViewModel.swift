//
//  GlucoseTrendViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class GlucoseTrendViewModel {
    let title = "血糖趋势"
    let rangeOptions = TrendRange.allCases

    private let repository: any GlucoseRepository

    var selectedRange: TrendRange = .today
    private(set) var readings: [GlucoseReading] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    var isShowingError = false

    init(repository: any GlucoseRepository) {
        self.repository = repository
    }

    var metrics: [DashboardMetric] {
        let summary = GlucoseMetricsCalculator.calculate(readings: readings)
        return [
            DashboardMetric(
                title: "范围内记录",
                value: summary.inRangePercentage.map { "\($0)%" } ?? "—",
                caption: "目标 3.9–10.0 mmol/L",
                systemImage: "target",
                tint: Color.brandLeaf
            ),
            DashboardMetric(
                title: "平均血糖",
                value: summary.average.map(formatted) ?? "—",
                caption: "mmol/L",
                systemImage: "number",
                tint: Color.brandTeal
            ),
            DashboardMetric(
                title: "最高记录",
                value: summary.maximum.map(formatted) ?? "—",
                caption: "mmol/L",
                systemImage: "arrow.up.right",
                tint: Color.brandAmber
            ),
            DashboardMetric(
                title: "偏低记录",
                value: "\(summary.lowReadingCount)",
                caption: rangeCaption,
                systemImage: "shield.checkered",
                tint: Color.brandRose
            )
        ]
    }

    var insights: [Insight] {
        guard !readings.isEmpty else { return [] }
        let summary = GlucoseMetricsCalculator.calculate(readings: readings)
        var items = [
            Insight(
                icon: "checkmark.seal",
                title: "本范围共有 \(summary.readingCount) 条记录",
                detail: "这里只统计实际保存的读数，不把零散记录描述为连续血糖时间占比。"
            )
        ]

        if let percentage = summary.inRangePercentage {
            items.append(
                Insight(
                    icon: "target",
                    title: "\(percentage)% 的记录位于目标范围",
                    detail: "目标范围暂按 3.9–10.0 mmol/L 展示，医疗决策请遵循医生建议。"
                )
            )
        }
        return items
    }

    var trendTitle: String {
        "\(selectedRange.rawValue)曲线"
    }

    var statusLabel: String {
        guard readings.count >= 3 else { return "数据较少" }
        let percentage = GlucoseMetricsCalculator.calculate(readings: readings).inRangePercentage ?? 0
        return percentage >= 80 ? "大多在范围" : "存在波动"
    }

    var statusTint: Color {
        guard readings.count >= 3 else { return Color.secondary }
        let percentage = GlucoseMetricsCalculator.calculate(readings: readings).inRangePercentage ?? 0
        return percentage >= 80 ? Color.brandLeaf : Color.brandAmber
    }

    var rangeCaption: String {
        switch selectedRange {
        case .today:
            "今天"
        case .week:
            "近 7 天"
        case .month:
            "近 30 天"
        }
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            readings = try repository.readings(in: selectedInterval)
            errorMessage = nil
            isShowingError = false
        } catch {
            errorMessage = "读取趋势数据失败：\(error.localizedDescription)"
            isShowingError = true
        }
    }

    func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !readings.isEmpty else { return [] }
        let values = readings.map(\.value)
        let minimum = min(3.0, (values.min() ?? 3.0) - 0.5)
        let maximum = max(11.0, (values.max() ?? 11.0) + 0.5)
        let valueRange = max(maximum - minimum, 1)
        let widthStep = size.width / CGFloat(max(readings.count - 1, 1))

        return readings.enumerated().map { index, reading in
            let normalized = (reading.value - minimum) / valueRange
            let y = size.height - (CGFloat(normalized) * size.height)
            return CGPoint(x: CGFloat(index) * widthStep, y: min(max(y, 8), size.height - 8))
        }
    }

    func axisLabel(for reading: GlucoseReading) -> String {
        switch selectedRange {
        case .today:
            reading.measuredAt.formatted(.dateTime.hour().minute())
        case .week:
            reading.measuredAt.formatted(.dateTime.weekday(.narrow))
        case .month:
            reading.measuredAt.formatted(.dateTime.day())
        }
    }

    private var selectedInterval: DateInterval {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? .distantFuture
        let dayCount: Int
        switch selectedRange {
        case .today:
            dayCount = 1
        case .week:
            dayCount = 7
        case .month:
            dayCount = 30
        }
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: todayStart) ?? .distantPast
        return DateInterval(start: start, end: tomorrow)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
