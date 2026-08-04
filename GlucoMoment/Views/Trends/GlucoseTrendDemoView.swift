//
//  GlucoseTrendDemoView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

struct GlucoseTrendDemoView: View {
    @State private var viewModel: GlucoseTrendViewModel

    init(repository: any GlucoseRepository) {
        _viewModel = State(initialValue: GlucoseTrendViewModel(repository: repository))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: viewModel.title) {
            Picker("时间范围", selection: $viewModel.selectedRange) {
                ForEach(viewModel.rangeOptions) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.readings.isEmpty {
                ContentUnavailableView {
                    Label("暂无趋势数据", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("在今日页记录血糖后，这里会按 mmol/L 展示趋势。")
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                TrendChartCard(viewModel: viewModel)
            }

            TrendMetricsGrid(metrics: viewModel.metrics)

            if !viewModel.insights.isEmpty {
                SectionHeader("数据说明")
                VStack(spacing: 10) {
                    ForEach(viewModel.insights) { insight in
                        InsightRow(insight: insight)
                    }
                }
            }
        }
        .refreshable(action: viewModel.load)
        .task(viewModel.load)
        .onChange(of: viewModel.selectedRange) {
            viewModel.load()
        }
        .alert("读取失败", isPresented: $viewModel.isShowingError) {
        } message: {
            Text(viewModel.errorMessage ?? "请稍后重试。")
        }
    }
}

private struct TrendChartCard: View {
    let viewModel: GlucoseTrendViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(viewModel.trendTitle, subtitle: "目标范围 3.9–10.0 mmol/L")
                Spacer()
                PillTag(title: viewModel.statusLabel, tint: viewModel.statusTint)
            }

            TrendChart(readings: viewModel.readings) { size in
                viewModel.chartPoints(in: size)
            }
            .frame(height: 210)

            HStack {
                ForEach(axisReadings) { reading in
                    Text(viewModel.axisLabel(for: reading))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var axisReadings: [GlucoseReading] {
        guard viewModel.readings.count > 6 else { return viewModel.readings }
        let step = max(viewModel.readings.count / 6, 1)
        var result = stride(from: 0, to: viewModel.readings.count, by: step).map { viewModel.readings[$0] }
        if result.last?.id != viewModel.readings.last?.id,
           let last = viewModel.readings.last {
            result.append(last)
        }
        return result
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
                        .accessibilityLabel(
                            "\(readings[index].value.formatted(.number.precision(.fractionLength(1)))) mmol/L，\(readings[index].state.label)"
                        )
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
    let dependencies = AppDependencies.preview()
    NavigationStack {
        GlucoseTrendDemoView(repository: dependencies.glucoseRepository)
    }
    .modelContainer(dependencies.modelContainer)
}
