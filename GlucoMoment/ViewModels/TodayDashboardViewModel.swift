//
//  TodayDashboardViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TodayDashboardViewModel {
    let title = "稳糖食刻"

    private let repository: any GlucoseRepository

    private(set) var readings: [GlucoseReading] = []
    /// 今天最新的一条血糖；今天没有记录时为 nil，首卡显示空状态。
    private(set) var latestReading: GlucoseReading?
    /// 今天之前最近的一条血糖，仅用于在空状态中提示“上次记录”。
    private(set) var previousReading: GlucoseReading?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    var isShowingError = false

    init(repository: any GlucoseRepository) {
        self.repository = repository
    }

    var timelineSubtitle: String {
        readings.isEmpty ? "今天还没有血糖记录" : "今天共有 \(readings.count) 条血糖记录"
    }

    var currentSnapshot: CurrentGlucoseSnapshot? {
        guard let latestReading else { return nil }
        return CurrentGlucoseSnapshot(
            value: formatted(latestReading.value),
            unit: "mmol/L",
            stateLabel: latestReading.state.label,
            stateTint: latestReading.state.tint,
            measuredAt: latestReading.measuredAt
        )
    }

    var previousSnapshot: CurrentGlucoseSnapshot? {
        guard latestReading == nil, let previousReading else { return nil }
        return CurrentGlucoseSnapshot(
            value: formatted(previousReading.value),
            unit: "mmol/L",
            stateLabel: previousReading.state.label,
            stateTint: previousReading.state.tint,
            measuredAt: previousReading.measuredAt
        )
    }

    var metrics: [DashboardMetric] {
        let summary = GlucoseMetricsCalculator.calculate(readings: readings)
        return [
            DashboardMetric(
                title: "范围内记录",
                value: summary.inRangePercentage.map { "\($0)%" } ?? "—",
                caption: "目标 3.9–10.0mmol/L",
                systemImage: "scope",
                tint: Color.brandTeal
            ),
            DashboardMetric(
                title: "平均血糖",
                value: summary.average.map(formatted) ?? "—",
                caption: "mmol/L",
                systemImage: "number",
                tint: Color.brandAmber
            ),
            DashboardMetric(
                title: "今日最高",
                value: summary.maximum.map(formatted) ?? "—",
                caption: "mmol/L",
                systemImage: "waveform.path.ecg",
                tint: Color.brandRose
            ),
            DashboardMetric(
                title: "记录次数",
                value: "\(summary.readingCount)",
                caption: "今天",
                systemImage: "checkmark.seal",
                tint: Color.brandLeaf
            )
        ]
    }

    var nextAction: String {
        guard let latestReading else {
            guard previousReading != nil else {
                return "记录第一条血糖，开始建立属于你的趋势。"
            }
            // 今天尚无记录时，按时段给出更具体的测量时机提示。
            let hour = Calendar.current.component(.hour, from: .now)
            if hour < 10 {
                return "今天还没有记录。起床后、早餐前测一次空腹血糖，是了解一天状态的好起点。"
            }
            return "今天还没有记录。可以在下一餐前测一次，餐后 2 小时再测一次，对照饮食影响。"
        }

        switch latestReading.state {
        case .low:
            return "这条记录低于目标范围。如有不适或读数异常，请按医嘱处理并联系医生。"
        case .inRange:
            return "继续按计划记录餐前或餐后血糖，数据越完整越容易发现规律。"
        case .elevated:
            return "可以补充记录附近的餐食和活动，方便后续回顾；医疗决策请咨询医生。"
        }
    }

    var compactReadings: ArraySlice<GlucoseReading> {
        readings.suffix(8)
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            readings = try repository.readings(in: todayInterval)
            // readings 按测量时间升序返回，最后一条即今日最新。
            latestReading = readings.last
            if latestReading == nil {
                previousReading = try repository.latestReading()
            } else {
                previousReading = nil
            }
            errorMessage = nil
            isShowingError = false
        } catch {
            errorMessage = "读取血糖记录失败：\(error.localizedDescription)"
            isShowingError = true
        }
    }

    func delete(_ reading: GlucoseReading) async {
        do {
            try await repository.delete(id: reading.id)
            load()
        } catch {
            errorMessage = "删除血糖记录失败：\(error.localizedDescription)"
            isShowingError = true
        }
    }

    private var todayInterval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .distantFuture
        return DateInterval(start: start, end: end)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
