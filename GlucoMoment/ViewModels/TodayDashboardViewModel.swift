//
//  TodayDashboardViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Observation
import SwiftUI

@Observable
final class TodayDashboardViewModel {
    let title = "稳糖食刻"
    let timelineSubtitle = "Demo 数据用于呈现模块结构，后续可接 HealthKit 或手动记录。"
    let nextAction = "20:40 记录晚餐后 2 小时血糖；如果高于 180，优先标注餐食和活动。"

    let readings: [GlucoseReading]
    let metrics: [DashboardMetric]
    let timelineEvents: [TimelineEvent]
    let currentSnapshot: CurrentGlucoseSnapshot

    init(
        readings: [GlucoseReading] = DemoDataProvider.readings,
        timelineEvents: [TimelineEvent] = DemoDataProvider.timelineEvents
    ) {
        self.readings = readings
        self.timelineEvents = timelineEvents
        self.currentSnapshot = CurrentGlucoseSnapshot(
            value: "112",
            unit: "mg/dL",
            stateLabel: "平稳区间",
            stateTint: Color.brandLeaf
        )
        self.metrics = [
            DashboardMetric(title: "今日范围", value: "84%", caption: "目标 70-180 mg/dL", systemImage: "scope", tint: Color.brandTeal),
            DashboardMetric(title: "餐后峰值", value: "152", caption: "午餐后 58 分钟", systemImage: "waveform.path.ecg", tint: Color.brandAmber),
            DashboardMetric(title: "活跃分钟", value: "26", caption: "餐后步行已达标", systemImage: "figure.walk", tint: Color.brandLeaf),
            DashboardMetric(title: "记录完整度", value: "3/4", caption: "晚间复测待完成", systemImage: "checkmark.seal", tint: Color.brandRose)
        ]
    }

    var compactReadings: ArraySlice<GlucoseReading> {
        readings.suffix(6)
    }
}
