//
//  GlucoseTrendDemoView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

struct GlucoseTrendDemoView: View {
    @State private var viewModel: GlucoseTrendViewModel
    @State private var reviewViewModel: MealReviewViewModel
    @State private var isShowingReviewConsent = false
    private let reviewSettings: MealReviewSettings
    private let foodAnalysisSettings: FoodAnalysisSettings
    private let healthDataRevision: Int

    init(
        repository: any GlucoseRepository,
        mealRepository: any MealRepository,
        reviewService: any MealReviewService,
        reviewSettings: MealReviewSettings,
        reviewCache: any MealReviewCacheStoring,
        foodAnalysisSettings: FoodAnalysisSettings,
        healthDataRevision: Int = 0
    ) {
        _viewModel = State(initialValue: GlucoseTrendViewModel(repository: repository))
        _reviewViewModel = State(initialValue: MealReviewViewModel(
            glucoseRepository: repository,
            mealRepository: mealRepository,
            service: reviewService,
            settings: reviewSettings,
            cache: reviewCache
        ))
        self.reviewSettings = reviewSettings
        self.foodAnalysisSettings = foodAnalysisSettings
        self.healthDataRevision = healthDataRevision
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
                    Text("手动记录或从健康 App 同步血糖后，这里会按 mmol/L 展示趋势。")
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                TrendChartCard(viewModel: viewModel)
            }

            TrendMetricsGrid(metrics: viewModel.metrics)

            SectionHeader("近期复盘", subtitle: "最近 \(MealReviewPayloadBuilder.reviewDays) 天")
            MealReviewCard(viewModel: reviewViewModel) {
                isShowingReviewConsent = true
            }

            if !viewModel.insights.isEmpty {
                SectionHeader("数据说明")
                VStack(spacing: 10) {
                    ForEach(viewModel.insights) { insight in
                        InsightRow(insight: insight)
                    }
                }
            }
        }
        .refreshable {
            viewModel.load()
            await reviewViewModel.load()
        }
        .task(id: healthDataRevision) {
            viewModel.load()
            await reviewViewModel.load()
        }
        .onChange(of: reviewSettings.isEnabled) {
            Task { await reviewViewModel.load() }
        }
        .sheet(isPresented: $isShowingReviewConsent) {
            MealReviewConsentView(destination: foodAnalysisSettings.reviewDestinationDescription) {
                Task { await reviewViewModel.enable() }
            }
        }
        .onChange(of: viewModel.selectedRange) {
            viewModel.load()
        }
        .alert("读取失败", isPresented: $viewModel.isShowingError) {
        } message: {
            Text(viewModel.errorMessage ?? "请稍后重试。")
        }
    }
}

/// 近期复盘卡片：按 `MealReviewViewModel.State` 显示开启引导、数据不足、生成按钮或结果
private struct MealReviewCard: View {
    let viewModel: MealReviewViewModel
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.state {
            case .disabled:
                Text("开启后，App 会把最近 \(MealReviewPayloadBuilder.reviewDays) 天每餐的餐后血糖摘要交给 AI，写出最多 3 条可以用自己的血糖去验证的小建议。数字由 App 在本机计算。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("开启 AI 复盘", systemImage: "text.magnifyingglass", action: onEnable)
                    .buttonStyle(.borderedProminent)
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .insufficient(let mealCount):
                Label("还需要更多记录", systemImage: "hourglass")
                    .font(.subheadline.weight(.semibold))
                Text("至少要有 \(MealReviewViewModel.minimumMealCount) 餐带连续血糖数据，现在有 \(mealCount) 餐。用拍照识别记录每一餐，并保持 CGM 同步到健康 App。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .ready(let mealCount):
                Text("最近 \(MealReviewPayloadBuilder.reviewDays) 天有 \(mealCount) 餐带连续血糖数据，可以生成复盘。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("生成复盘", systemImage: "sparkles") {
                    Task { await viewModel.generate() }
                }
                .buttonStyle(.borderedProminent)
            case .generating:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在生成复盘…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let review, let generatedAt, let serviceError):
                if let notice = review.safetyNotice {
                    Label(notice, systemImage: "exclamationmark.shield")
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.brandAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(Array(review.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .font(.subheadline)
                        Text(item.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Self.footnote(review: review, serviceError: serviceError))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(generatedAt, format: GlucoMomentDateStyle.monthDayTime)
                        .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("重新生成", systemImage: "arrow.clockwise") {
                        Task { await viewModel.generate() }
                    }
                    .font(.subheadline)
                }
            case .failed(let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("重试", systemImage: "arrow.clockwise") {
                    Task { await viewModel.load() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private static func footnote(review: MealReview, serviceError: String?) -> String {
        let origin = if let serviceError {
            "AI 暂时不可用（\(serviceError)），以下由本地模板生成。"
        } else if review.isFallback {
            "AI 的结果没有通过 App 的校验，以下由本地模板生成。"
        } else {
            "由 AI 撰写，App 校验后填入本机计算的数字。"
        }
        return origin + "仅供饮食记录参考，不是诊断；调整饮食或用药请咨询医生或营养师。"
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
                        .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
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
        GlucoseTrendDemoView(
            repository: dependencies.glucoseRepository,
            mealRepository: dependencies.mealRepository,
            reviewService: dependencies.mealReviewService,
            reviewSettings: dependencies.mealReviewSettings,
            reviewCache: dependencies.mealReviewCache,
            foodAnalysisSettings: dependencies.foodAnalysisSettings
        )
    }
    .modelContainer(dependencies.modelContainer)
}
