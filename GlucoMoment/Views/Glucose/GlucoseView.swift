//
//  GlucoseView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 「血糖」标签页，版式参考「健康」App 的数据详情：最新读数 → 时间范围 → 图表 → 统计 → 所有记录。
/// 餐后血糖和 AI 复盘放在「复盘」标签页
struct GlucoseView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: GlucoseTrendViewModel
    @State private var latestViewModel: TodayDashboardViewModel
    @State private var glucoseEditor: GlucoseEditorPresentation?
    @State private var isShowingGlucoseTarget = false
    @State private var isShowingDayPicker = false

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

                if !targetSettings.isConfigured, !targetSettings.isHintDismissed {
                    targetHint
                }

                Picker("时间范围", selection: $viewModel.selectedRange) {
                    ForEach(viewModel.rangeOptions) { range in
                        Text(range.shortTitle).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                periodNavigator

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
        // 大标题和右上角按钮同一行，与 App Store、音乐一致
        .toolbarTitleDisplayMode(.inlineLarge)
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
        .sheet(isPresented: $isShowingGlucoseTarget) {
            GlucoseTargetView(settings: targetSettings, repository: dependencies.glucoseRepository)
                .tint(Color.brandTeal)
        }
        .sheet(isPresented: $isShowingDayPicker) {
            DayPickerSheet(
                title: viewModel.selectedRange == .today ? "选择日期" : "选择截止日期",
                selectedDate: viewModel.endDay,
                range: viewModel.earliestEndDay...viewModel.today
            ) { day in
                viewModel.select(endDay: day)
            }
        }
        // 切换日 / 周 / 月和前后翻页都会改变时间段
        .onChange(of: viewModel.interval) {
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

    private var targetSettings: GlucoseTargetSettings { dependencies.glucoseTargetSettings }

    private func reload() {
        viewModel.load()
        latestViewModel.load()
    }

    // MARK: 目标范围提示

    /// 还没设置过目标范围时提示一次，可关掉
    private var targetHint: some View {
        HStack(spacing: 12) {
            Button {
                isShowingGlucoseTarget = true
            } label: {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "scope", tint: .glucoseTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("设置你的血糖目标范围")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("目前按 3.9–10.0 mmol/L 显示，可按自己的情况调整")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("不再提示", systemImage: "xmark") {
                withAnimation(.smooth) { targetSettings.isHintDismissed = true }
            }
            .labelStyle(.iconOnly)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    // MARK: 最新读数

    private var latestCard: some View {
        SummaryCard(
            title: "最新",
            systemImage: "drop.fill",
            tint: .glucoseTint
        ) {
            latestContent
        }
    }

    @ViewBuilder
    private var latestContent: some View {
        if let latest = latestViewModel.latestReading {
            VStack(alignment: .leading, spacing: 6) {
                MetricValueText(value: DisplayFormat.glucose(latest.value), unit: "mmol/L")
                measuredAtText(latest.measuredAt)
                Label(latest.state.phrase, systemImage: "circle.fill")
                    .labelStyle(StatusDotLabelStyle(tint: latest.state.tint))
                    .font(.footnote.weight(.medium))
            }
        } else if let previous = latestViewModel.previousReading {
            VStack(alignment: .leading, spacing: 6) {
                MetricValueText(value: DisplayFormat.glucose(previous.value), unit: "mmol/L")
                    .foregroundStyle(.secondary)
                measuredAtText(previous.measuredAt)
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

    /// 读数下方的测量时间，带日期，例如「11/1 01:55」
    private func measuredAtText(_ date: Date) -> some View {
        Text(date.formatted(GlucoMomentDateStyle.numericMonthDayTime))
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    // MARK: 时间段切换

    /// 分段控件下方：左边是当前时间段，点按弹出日历；右边「今天」和前后翻页，与饮食页的日期行一致
    private var periodNavigator: some View {
        HStack(spacing: 4) {
            Button {
                isShowingDayPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(periodTitle)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandTeal)
                .contentTransition(.numericText())
            }
            .buttonStyle(.borderless)
            .accessibilityHint(viewModel.selectedRange == .today ? "选择要查看的日期" : "选择时间段的最后一天")

            Spacer(minLength: 8)

            Button("今天") {
                withAnimation(.snappy) { viewModel.showToday() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .tint(Color.brandTeal)
            .disabled(viewModel.isShowingToday)
            .padding(.trailing, 6)

            pageButton("chevron.left", label: "前\(pageLabel)", enabled: viewModel.canGoBack) {
                viewModel.showPrevious()
            }
            pageButton("chevron.right", label: "后\(pageLabel)", enabled: viewModel.canGoForward) {
                viewModel.showNext()
            }
        }
        .padding(.horizontal, 4)
    }

    private func pageButton(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: systemImage) {
            withAnimation(.snappy) { action() }
        }
        .labelStyle(.iconOnly)
        .font(.subheadline.weight(.semibold))
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .buttonStyle(.borderless)
        .tint(Color.brandTeal)
        .disabled(!enabled)
    }

    private var pageLabel: String {
        switch viewModel.selectedRange {
        case .today: "一天"
        case .week: "7 天"
        case .month: "30 天"
        }
    }

    /// 例如「今天」「10月31日 周六」「10月26日–11月1日」；不在今年时带上年份
    private var periodTitle: String {
        let calendar = Calendar.current
        let interval = viewModel.interval
        let lastDay = viewModel.endDay
        let needsYear = !calendar.isDate(interval.start, equalTo: viewModel.today, toGranularity: .year)
        var style = Date.FormatStyle().month(.abbreviated).day().locale(GlucoMomentDateStyle.mainlandChinaLocale)
        if needsYear {
            style = style.year()
        }

        if viewModel.selectedRange == .today {
            return viewModel.isShowingToday ? "今天" : lastDay.formatted(style.weekday(.abbreviated))
        }
        return "\(interval.start.formatted(style))–\(lastDay.formatted(style))"
    }

    /// 与 `GlucoseTrendViewModel` 读取数据的范围一致
    private var domain: ClosedRange<Date> {
        viewModel.interval.start...viewModel.interval.end
    }

    // MARK: 图表与统计

    @ViewBuilder
    private var chartCard: some View {
        if viewModel.readings.isEmpty {
            ContentUnavailableView {
                Label(viewModel.isShowingToday ? "暂无血糖数据" : "这段时间没有记录", systemImage: "chart.xyaxis.line")
            } description: {
                if viewModel.isShowingToday {
                    Text("手动记录，或在设置里连接健康 App 同步血糖。")
                } else {
                    Text("健康 App 每次同步最近 30 天，更早的记录只有之前同步过的才会保留。")
                }
            } actions: {
                if viewModel.isShowingToday {
                    Button("记录血糖") { glucoseEditor = .newReading }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
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

    /// 第一行是读数落在目标范围内、偏高、偏低的占比（相加为 100%），第二行是平均、最高、最低值。
    /// CGM 读数很密，次数没有参考意义，所以第一行用占比（国际 TIR 共识的 TIR / TAR / TBR）
    private var statsCard: some View {
        let summary = GlucoseMetricsCalculator.calculate(readings: viewModel.readings, targetRange: .current)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(summary.readingCount) 次读数")
                Spacer(minLength: 8)
                // 第二行三个数共用一个单位，避免窄屏上挤不下
                Text("血糖单位 mmol/L")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    stat("目标范围内", value: percentText(summary.inRangePercentage), unit: "%", tint: Color.stableScore(90))
                    stat("偏高", value: percentText(summary.aboveRangePercentage), unit: "%", tint: summary.highReadingCount > 0 ? GlucoseState.elevated.tint : .primary)
                    stat("偏低", value: percentText(summary.belowRangePercentage), unit: "%", tint: summary.lowReadingCount > 0 ? GlucoseState.low.tint : .primary)
                }
                Divider()
                    .gridCellColumns(3)
                GridRow {
                    stat("平均", value: glucoseText(summary.average))
                    stat("最高", value: glucoseText(summary.maximum))
                    stat("最低", value: glucoseText(summary.minimum))
                }
            }
        }
        .cardBackground()
        .animation(.smooth, value: summary)
    }

    private func percentText(_ percentage: Int?) -> String {
        percentage.map { "\($0)" } ?? "—"
    }

    private func glucoseText(_ value: Double?) -> String {
        value.map(DisplayFormat.glucose) ?? "—"
    }

    private func stat(_ title: String, value: String, unit: String? = nil, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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
