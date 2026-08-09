//
//  GlucoseHistoryViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class GlucoseHistoryViewModel {
    private let repository: any GlucoseRepository

    var selectedDate: Date
    private(set) var readings: [GlucoseReading] = []
    private(set) var errorMessage: String?

    init(repository: any GlucoseRepository, initialDate: Date? = nil) {
        self.repository = repository
        selectedDate = initialDate ?? Self.defaultHistoryDate
    }

    var recordSubtitle: String {
        if readings.isEmpty {
            "当天暂无记录"
        } else {
            "当天共 \(readings.count) 条记录"
        }
    }

    var metrics: [DashboardMetric] {
        let summary = GlucoseMetricsCalculator.calculate(readings: readings)
        return [
            DashboardMetric(
                title: "平均血糖",
                value: summary.average?.formatted(
                    .number.precision(.fractionLength(1))
                ) ?? "—",
                caption: "mmol/L",
                systemImage: "number",
                tint: Color.brandAmber
            ),
            DashboardMetric(
                title: "范围内记录",
                value: summary.inRangePercentage.map { "\($0)%" } ?? "—",
                caption: "目标 3.9–10.0",
                systemImage: "scope",
                tint: Color.brandTeal
            ),
            DashboardMetric(
                title: "最高血糖",
                value: summary.maximum?.formatted(
                    .number.precision(.fractionLength(1))
                ) ?? "—",
                caption: "mmol/L",
                systemImage: "arrow.up.right",
                tint: Color.brandRose
            ),
            DashboardMetric(
                title: "记录次数",
                value: "\(summary.readingCount)",
                caption: "当天",
                systemImage: "checkmark.seal",
                tint: Color.brandLeaf
            )
        ]
    }

    func load() {
        guard let interval = Calendar.current.dateInterval(of: .day, for: selectedDate) else {
            readings = []
            errorMessage = "无法确定所选日期的时间范围。"
            return
        }

        do {
            readings = try repository.readings(in: interval)
            errorMessage = nil
        } catch {
            readings = []
            errorMessage = "读取历史血糖失败：(error.localizedDescription)"
        }
    }

    private static var defaultHistoryDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    }
}
