//
//  GlucoseTrendChart.swift
//  GlucoMoment
//

import Charts
import SwiftUI

/// 趋势页的主图。「今日」画折线；「7 天」「30 天」每天一根从最低到最高的范围条，与「健康」App 的血糖图一致。
/// 按住拖动可以查看某个时刻或某一天的数值
struct GlucoseTrendChart: View {
    let readings: [GlucoseReading]
    let range: TrendRange
    let domain: ClosedRange<Date>

    @State private var selection: Date?

    private let target = GlucoseTargetRange.standard
    private let calendar = Calendar.current

    struct DayRange: Identifiable {
        let day: Date
        let minimum: Double
        let maximum: Double
        let average: Double
        let count: Int

        var id: Date { day }
    }

    var body: some View {
        Chart {
            targetBand
            if range == .today {
                dayLine
            } else {
                dailyRanges
            }
            selectionMarks
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartXAxis { xAxis }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [4, 7, 10, 13].filter { yDomain.contains($0) })
        }
        .chartXSelection(value: $selection)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: 图层

    @ChartContentBuilder
    private var targetBand: some ChartContent {
        RectangleMark(
            yStart: .value("下限", target.lowerBound),
            yEnd: .value("上限", target.upperBound)
        )
        .foregroundStyle(Color.targetBandFill)
    }

    @ChartContentBuilder
    private var dayLine: some ChartContent {
        ForEach(readings) { reading in
            LineMark(
                x: .value("时间", reading.measuredAt),
                y: .value("血糖", reading.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.glucoseTint)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        ForEach(readings.count <= 24 ? readings : []) { reading in
            PointMark(
                x: .value("时间", reading.measuredAt),
                y: .value("血糖", reading.value)
            )
            .symbolSize(28)
            .foregroundStyle(reading.state.tint)
        }
    }

    @ChartContentBuilder
    private var dailyRanges: some ChartContent {
        ForEach(dayRanges) { day in
            BarMark(
                x: .value("日期", day.day, unit: .day),
                yStart: .value("最低", day.minimum),
                yEnd: .value("最高", max(day.maximum, day.minimum + 0.25)),
                width: .ratio(range == .week ? 0.35 : 0.55)
            )
            .clipShape(Capsule())
            .foregroundStyle(Color.glucoseTint.gradient)
            .opacity(selectedDay == nil || selectedDay?.day == day.day ? 1 : 0.35)
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if range == .today, let reading = selectedReading {
            RuleMark(x: .value("选中", reading.measuredAt))
                .foregroundStyle(.secondary.opacity(0.4))
                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    selectionBubble(
                        value: "\(DisplayFormat.glucose(reading.value)) mmol/L",
                        caption: reading.measuredAt.formatted(GlucoMomentDateStyle.time)
                    )
                }
        } else if range != .today, let day = selectedDay {
            RuleMark(x: .value("选中", day.day, unit: .day))
                .foregroundStyle(.secondary.opacity(0.25))
                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    selectionBubble(
                        value: "\(DisplayFormat.glucose(day.minimum))–\(DisplayFormat.glucose(day.maximum)) mmol/L",
                        caption: "\(day.day.formatted(.dateTime.month(.abbreviated).day().locale(GlucoMomentDateStyle.mainlandChinaLocale))) · \(day.count) 次"
                    )
                }
        }
    }

    private func selectionBubble(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.footnote.weight(.semibold).monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    // MARK: 坐标轴

    private var xAxis: some AxisContent {
        AxisMarks(values: xAxisValues) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(axisLabel(for: date))
                }
            }
        }
    }

    private var xAxisValues: AxisMarkValues {
        switch range {
        case .today: .stride(by: .hour, count: 6)
        case .week: .stride(by: .day)
        case .month: .stride(by: .day, count: 7)
        }
    }

    private func axisLabel(for date: Date) -> String {
        switch range {
        case .today:
            "\(calendar.component(.hour, from: date)) 时"
        case .week:
            date.formatted(GlucoMomentDateStyle.weekday)
        case .month:
            "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
        }
    }

    // MARK: 数据

    var dayRanges: [DayRange] {
        Dictionary(grouping: readings) { calendar.startOfDay(for: $0.measuredAt) }
            .map { day, values in
                let numbers = values.map(\.value)
                return DayRange(
                    day: day,
                    minimum: numbers.min() ?? 0,
                    maximum: numbers.max() ?? 0,
                    average: numbers.reduce(0, +) / Double(max(numbers.count, 1)),
                    count: numbers.count
                )
            }
            .sorted { $0.day < $1.day }
    }

    private var selectedReading: GlucoseReading? {
        guard let selection else { return nil }
        return readings.min {
            abs($0.measuredAt.timeIntervalSince(selection)) < abs($1.measuredAt.timeIntervalSince(selection))
        }
    }

    private var selectedDay: DayRange? {
        guard let selection else { return nil }
        return dayRanges.first { calendar.isDate($0.day, inSameDayAs: selection) }
    }

    private var yDomain: ClosedRange<Double> {
        let values = readings.map(\.value)
        let lower = min(3.0, (values.min() ?? 4) - 0.5)
        let upper = max(12.0, (values.max() ?? 10) + 0.8)
        return lower...upper
    }

    private var accessibilitySummary: String {
        guard let minimum = readings.map(\.value).min(), let maximum = readings.map(\.value).max() else {
            return "没有血糖数据"
        }
        return "血糖图，共 \(readings.count) 次读数，最低 \(DisplayFormat.glucose(minimum))，最高 \(DisplayFormat.glucose(maximum)) mmol/L"
    }
}
