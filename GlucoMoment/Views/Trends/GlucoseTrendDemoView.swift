//
//  GlucoseTrendDemoView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

struct GlucoseTrendDemoView: View {
    @State private var viewModel = GlucoseTrendViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: viewModel.title) {
            Picker("时间范围", selection: $viewModel.selectedRange) {
                ForEach(viewModel.rangeOptions) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            TrendChartCard(viewModel: viewModel)
            TrendMetricsGrid(metrics: viewModel.metrics)

            SectionHeader("洞察")
            VStack(spacing: 10) {
                ForEach(viewModel.insights) { insight in
                    InsightRow(insight: insight)
                }
            }
        }
    }
}

private struct TrendChartCard: View {
    let viewModel: GlucoseTrendViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(viewModel.trendTitle, subtitle: "目标区间 70-180 mg/dL")
                Spacer()
                PillTag(title: viewModel.statusLabel, tint: viewModel.statusTint)
            }

            TrendChart(readings: viewModel.readings) { size in
                viewModel.chartPoints(in: size)
            }
            .frame(height: 210)

            HStack {
                ForEach(viewModel.readings) { reading in
                    Text(reading.hour.prefix(2))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TrendChart: View {
    let readings: [GlucoseReading]
    let points: (CGSize) -> [CGPoint]

    var body: some View {
        GeometryReader { proxy in
            let chartPoints = points(proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.brandMint.opacity(0.38))
                    .frame(height: proxy.size.height * 0.58)
                    .frame(maxHeight: .infinity, alignment: .center)

                Path { path in
                    guard let first = chartPoints.first else { return }
                    path.move(to: first)
                    for point in chartPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.brandTeal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                ForEach(Array(zip(readings.indices, chartPoints)), id: \.0) { index, point in
                    Circle()
                        .fill(readings[index].state.tint)
                        .frame(width: 10, height: 10)
                        .position(point)
                }
            }
        }
    }
}

private struct TrendMetricsGrid: View {
    let metrics: [DashboardMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(metrics) { metric in
                MetricCard(metric: metric)
            }
        }
    }
}

private struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .foregroundStyle(Color.brandTeal)
                .frame(width: 34, height: 34)
                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                Text(insight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        GlucoseTrendDemoView()
    }
}
