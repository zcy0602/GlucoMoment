//
//  GlucoseView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 「血糖」标签页，版式参考「健康」App 的数据详情：最新读数 → 时间范围 → 平均值 → 图表 → 统计 → 所有记录。
/// 餐后血糖和 AI 复盘放在「复盘」标签页
struct GlucoseView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: GlucoseTrendViewModel
    @State private var latestViewModel: TodayDashboardViewModel
    @State private var glucoseEditor: GlucoseEditorPresentation?

    init(dependencies: AppDependencies, healthDataRevision: Int) {
        _viewModel = State(initialValue: GlucoseTrendViewModel(repository: dependencies.glucoseRepository))
        _latestViewModel = State(initialValue: TodayDashboardViewModel(repository: dependencies.glucoseRepository))
        self.dependencies = dependencies
        self.healthDataRevision = healthDataRevision
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                latestCard

                Picker("时间范围", selection: $viewModel.selectedRange) {
                    ForEach(viewModel.rangeOptions) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                headline

                chartCard

                if !viewModel.readings.isEmpty {
                    statsCard
                }

                NavigationLink {
                    GlucoseLogView(dependencies: dependencies, healthDataRevision: healthDataRevision)
                } label: {
                    HStack {
                        Label("所有血糖记录", systemImage: "list.bullet")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .cardBackground()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("血糖")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("记录血糖", systemImage: "plus") {
                    glucoseEditor = .newReading
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(dependencies: dependencies)
            }
        }
        .sheet(item: $glucoseEditor) { presentation in
            GlucoseEntryView(repository: dependencies.glucoseRepository, reading: presentation.reading) {
                reload()
            }
        }
        .onChange(of: viewModel.selectedRange) {
            withAnimation(.smooth) { viewModel.load() }
        }
        .refreshable {
            await dependencies.healthKitCoordinator.refresh()
            reload()
        }
        .task(id: healthDataRevision) {
            reload()
        }
    }

    private func reload() {
        viewModel.load()
        latestViewModel.load()
    }

    // MARK: 最新读数

    private var latestCard: some View {
        SummaryCard(
            title: "最新",
            systemImage: "drop.fill",
            tint: .glucoseTint,
            detail: latestDetail
        ) {
            latestContent
        }
    }

    private var latestDetail: String? {
        if let latest = latestViewModel.latestReading {
            return latest.measuredAt.formatted(GlucoMomentDateStyle.time)
        }
        if let previous = latestViewModel.previousReading {
            return previous.measuredAt.formatted(GlucoMomentDateStyle.monthDayTime)
        }
        return nil
    }

    @ViewBuilder
    private var latestContent: some View {
        if let latest = latestViewModel.latestReading {
            VStack(alignment: .leading, spacing: 6) {
                MetricValueText(value: DisplayFormat.glucose(latest.value), unit: "mmol/L")
                Label(latest.state.phrase, systemImage: "circle.fill")
                    .labelStyle(StatusDotLabelStyle(tint: latest.state.tint))
                    .font(.footnote.weight(.medium))
            }
        } else if let previous = latestViewModel.previousReading {
            VStack(alignment: .leading, spacing: 6) {
                MetricValueText(value: DisplayFormat.glucose(previous.value), unit: "mmol/L")
                    .foregroundStyle(.secondary)
                Text("今天还没有记录，这是上一次的读数")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text("还没有血糖记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("记录") { glucoseEditor = .newReading }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.glucoseTint)
            }
        }
    }

    // MARK: 标题数值

    private var summary: GlucoseMetrics {
        GlucoseMetricsCalculator.calculate(readings: viewModel.readings)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("平均")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            MetricValueText(
                value: summary.average.map(DisplayFormat.glucose) ?? "—",
                unit: "mmol/L"
            )
            Text(rangeDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .animation(.smooth, value: summary.average)
    }

    private var rangeDescription: String {
        let interval = domain
        let style = Date.FormatStyle().month(.abbreviated).day().locale(GlucoMomentDateStyle.mainlandChinaLocale)
        let dates: String
        if viewModel.selectedRange == .today {
            dates = "今天"
        } else {
            let end = interval.upperBound.addingTimeInterval(-1)
            dates = "\(interval.lowerBound.formatted(style))–\(end.formatted(style))"
        }
        return viewModel.readings.isEmpty ? "\(dates) · 暂无记录" : "\(dates) · \(summary.readingCount) 次读数"
    }

    /// 与 `GlucoseTrendViewModel` 读取数据的范围一致
    private var domain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? .now
        let days = switch viewModel.selectedRange {
        case .today: 1
        case .week: 7
        case .month: 30
        }
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return start...tomorrow
    }

    // MARK: 图表与统计

    @ViewBuilder
    private var chartCard: some View {
        if viewModel.readings.isEmpty {
            ContentUnavailableView {
                Label("暂无血糖数据", systemImage: "chart.xyaxis.line")
            } description: {
                Text("手动记录，或在设置里连接健康 App 同步血糖。")
            } actions: {
                Button("记录血糖") { glucoseEditor = .newReading }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity)
            .cardBackground(padding: 8)
        } else {
            GlucoseTrendChart(
                readings: viewModel.readings,
                range: viewModel.selectedRange,
                domain: domain
            )
            .frame(height: 240)
            .cardBackground()
        }
    }

    private var statsCard: some View {
        let minimum = viewModel.readings.map(\.value).min()
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                stat("目标范围内", value: summary.inRangePercentage.map { "\($0)" } ?? "—", unit: "%", tint: Color.stableScore(90))
                stat("偏低", value: "\(summary.lowReadingCount)", unit: "次", tint: summary.lowReadingCount > 0 ? GlucoseState.low.tint : .primary)
            }
            Divider()
                .gridCellColumns(2)
            GridRow {
                stat("最高", value: summary.maximum.map(DisplayFormat.glucose) ?? "—", unit: "mmol/L")
                stat("最低", value: minimum.map(DisplayFormat.glucose) ?? "—", unit: "mmol/L")
            }
        }
        .cardBackground()
    }

    private func stat(_ title: String, value: String, unit: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 状态文字前的小圆点
struct StatusDotLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            configuration.title
                .foregroundStyle(tint)
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        GlucoseView(dependencies: dependencies, healthDataRevision: 0)
    }
    .modelContainer(dependencies.modelContainer)
}
