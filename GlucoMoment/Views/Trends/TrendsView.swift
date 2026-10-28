//
//  TrendsView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 新版趋势页，版式参考「健康」App 的数据详情：时间范围 → 平均值 → 图表 → 统计 → AI 复盘
struct TrendsView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: GlucoseTrendViewModel
    @State private var reviewViewModel: MealReviewViewModel
    @State private var isShowingReviewConsent = false
    @State private var glucoseEditor: GlucoseEditorPresentation?

    init(dependencies: AppDependencies, healthDataRevision: Int) {
        _viewModel = State(initialValue: GlucoseTrendViewModel(repository: dependencies.glucoseRepository))
        _reviewViewModel = State(initialValue: MealReviewViewModel(
            glucoseRepository: dependencies.glucoseRepository,
            mealRepository: dependencies.mealRepository,
            service: dependencies.mealReviewService,
            settings: dependencies.mealReviewSettings,
            cache: dependencies.mealReviewCache
        ))
        self.dependencies = dependencies
        self.healthDataRevision = healthDataRevision
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                CardSectionTitle("AI 复盘", trailing: "最近 \(MealReviewPayloadBuilder.reviewDays) 天")
                MealReviewInsightCard(viewModel: reviewViewModel) {
                    isShowingReviewConsent = true
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
        .navigationTitle("趋势")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("记录血糖", systemImage: "plus") {
                    glucoseEditor = .newReading
                }
            }
        }
        .sheet(item: $glucoseEditor) { presentation in
            GlucoseEntryView(repository: dependencies.glucoseRepository, reading: presentation.reading) {
                viewModel.load()
            }
        }
        .sheet(isPresented: $isShowingReviewConsent) {
            MealReviewConsentView(destination: dependencies.foodAnalysisSettings.reviewDestinationDescription) {
                Task { await reviewViewModel.enable() }
            }
        }
        .onChange(of: viewModel.selectedRange) {
            withAnimation(.smooth) { viewModel.load() }
        }
        .onChange(of: dependencies.mealReviewSettings.isEnabled) {
            Task { await reviewViewModel.load() }
        }
        .refreshable {
            viewModel.load()
            await reviewViewModel.load()
        }
        .task(id: healthDataRevision) {
            viewModel.load()
            await reviewViewModel.load()
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

/// AI 复盘卡片：按 `MealReviewViewModel.State` 显示开启引导、进度、生成按钮或结果
struct MealReviewInsightCard: View {
    let viewModel: MealReviewViewModel
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch viewModel.state {
            case .disabled:
                intro(
                    title: "让 AI 看看你的餐后血糖",
                    text: "根据最近 \(MealReviewPayloadBuilder.reviewDays) 天每餐的餐后曲线，写出几条能用自己血糖验证的建议。"
                )
                Button(action: onEnable) {
                    Label("开启 AI 复盘", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.insightTint)
                .controlSize(.large)

            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)

            case .insufficient(let mealCount):
                intro(
                    title: "还差 \(MealReviewViewModel.minimumMealCount - mealCount) 餐",
                    text: "需要至少 \(MealReviewViewModel.minimumMealCount) 餐有完整的餐后血糖。记录每一餐，并让连续血糖仪同步到健康 App。"
                )
                ProgressView(value: Double(mealCount), total: Double(MealReviewViewModel.minimumMealCount))
                    .tint(.insightTint)

            case .ready(let mealCount):
                intro(
                    title: "可以生成复盘了",
                    text: "最近 \(MealReviewPayloadBuilder.reviewDays) 天有 \(mealCount) 餐带完整的餐后血糖。"
                )
                Button {
                    Task { await viewModel.generate() }
                } label: {
                    Label("生成复盘", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.insightTint)
                .controlSize(.large)

            case .generating:
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.insightTint)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text("正在看你最近的餐后血糖…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)

            case .loaded(let review, let generatedAt, let serviceError):
                loaded(review: review, generatedAt: generatedAt, serviceError: serviceError)

            case .failed(let message):
                intro(title: "暂时无法复盘", text: message)
                Button("重试", systemImage: "arrow.clockwise") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.bordered)
            }
        }
        .cardBackground()
    }

    private func intro(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: "sparkles", tint: .insightTint, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func loaded(review: MealReview, generatedAt: Date, serviceError: String?) -> some View {
        if let notice = review.safetyNotice {
            Label(notice, systemImage: "exclamationmark.shield.fill")
                .font(.subheadline)
                .foregroundStyle(GlucoseState.low.tint)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GlucoseState.low.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        ForEach(Array(review.items.enumerated()), id: \.offset) { index, item in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.insightTint, in: Circle())
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if index < review.items.count - 1 {
                Divider()
                    .padding(.leading, 34)
            }
        }

        HStack {
            Text(origin(review: review, serviceError: serviceError))
            Spacer()
            Button("重新生成", systemImage: "arrow.clockwise") {
                Task { await viewModel.generate() }
            }
            .labelStyle(.iconOnly)
            .tint(.insightTint)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)

        Text("仅供参考，不是诊断。调整饮食或用药请咨询医生。生成于 \(generatedAt.formatted(GlucoMomentDateStyle.monthDayTime))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func origin(review: MealReview, serviceError: String?) -> String {
        if serviceError != nil {
            return "AI 暂时不可用，以下由本机模板生成"
        }
        if review.isFallback {
            return "AI 的结果未通过校验，以下由本机模板生成"
        }
        return "AI 撰写 · 数字由本机计算"
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        TrendsView(dependencies: dependencies, healthDataRevision: 0)
    }
    .modelContainer(dependencies.modelContainer)
}
