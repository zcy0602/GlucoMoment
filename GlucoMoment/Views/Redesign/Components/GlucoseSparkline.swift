//
//  GlucoseSparkline.swift
//  GlucoMoment
//

import Charts
import SwiftUI

/// 卡片里的小曲线：没有坐标轴，只有目标范围底色、走势线和最后一个点
struct GlucoseSparkline: View {
    let readings: [GlucoseReading]
    /// 横轴范围；为 nil 时按数据自身范围
    var timeDomain: ClosedRange<Date>?

    private let range = GlucoseTargetRange.standard

    var body: some View {
        Chart {
            RectangleMark(
                yStart: .value("下限", range.lowerBound),
                yEnd: .value("上限", range.upperBound)
            )
            .foregroundStyle(Color.targetBandFill)

            ForEach(readings) { reading in
                LineMark(
                    x: .value("时间", reading.measuredAt),
                    y: .value("血糖", reading.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.glucoseTint)
            }

            if let last = readings.last {
                PointMark(
                    x: .value("时间", last.measuredAt),
                    y: .value("血糖", last.value)
                )
                .symbolSize(44)
                .foregroundStyle(last.state.tint)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
        .modifier(OptionalXDomain(domain: timeDomain))
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        let values = readings.map(\.value)
        let lower = min(range.lowerBound - 1, (values.min() ?? range.lowerBound) - 0.5)
        let upper = max(range.upperBound + 1, (values.max() ?? range.upperBound) + 0.5)
        return lower...upper
    }
}

private struct OptionalXDomain: ViewModifier {
    let domain: ClosedRange<Date>?

    func body(content: Content) -> some View {
        if let domain {
            content.chartXScale(domain: domain)
        } else {
            content
        }
    }
}

extension GlucoseState {
    /// 新版界面的状态文字，比「目标范围」更像一句话
    var phrase: String {
        switch self {
        case .low: "低于目标范围"
        case .inRange: "在目标范围内"
        case .elevated: "高于目标范围"
        }
    }
}

extension FoodCategory {
    /// 类别色，用在食物条目前的小圆点和评分依据页
    var tint: Color {
        switch self {
        case .refinedGrain: Color(red: 0.91, green: 0.62, blue: 0.18)
        case .wholeGrainLegume: Color(red: 0.62, green: 0.46, blue: 0.27)
        case .tuber: Color(red: 0.80, green: 0.52, blue: 0.34)
        case .addedSugar: Color(red: 0.93, green: 0.36, blue: 0.56)
        case .fruit: Color(red: 0.97, green: 0.46, blue: 0.24)
        case .dairy: Color(red: 0.36, green: 0.60, blue: 0.90)
        case .vegetable: Color.mealTint
        case .protein: Color(red: 0.84, green: 0.33, blue: 0.36)
        case .nutFat: Color(red: 0.66, green: 0.62, blue: 0.24)
        case .other: Color.gray
        }
    }
}

#Preview {
    let start = Calendar.current.startOfDay(for: .now)
    let values = [5.6, 6.2, 8.9, 10.8, 7.4, 6.1, 9.2, 7.0]
    let readings = values.enumerated().map { index, value in
        GlucoseReading(measuredAt: start.addingTimeInterval(Double(index) * 7_200 + 25_000), value: value)
    }
    GlucoseSparkline(readings: readings)
        .frame(width: 140, height: 60)
        .padding()
}
