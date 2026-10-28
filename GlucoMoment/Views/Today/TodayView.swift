//
//  TodayView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 新版「今天」页，参考「健康」App 的摘要：血糖、饮食两张主卡，下面是下一餐提示和最近的复盘。
/// 每张卡只回答一个问题，点开去对应的标签页看细节
struct TodayView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int
    let onShowTab: (RootTab) -> Void

    @State private var glucoseViewModel: TodayDashboardViewModel
    @State private var mealViewModel: MealLogViewModel
    @State private var reviewViewModel: MealReviewViewModel
    @State private var captureSource: MealPhotoSource?
    @State private var glucoseEditor: GlucoseEditorPresentation?
    @State private var isShowingSettings = false

    init(
        dependencies: AppDependencies,
        healthDataRevision: Int,
        onShowTab: @escaping (RootTab) -> Void
    ) {
        _glucoseViewModel = State(initialValue: TodayDashboardViewModel(repository: dependencies.glucoseRepository))
        _mealViewModel = State(initialValue: MealLogViewModel(repository: dependencies.mealRepository))
        _reviewViewModel = State(initialValue: MealReviewViewModel(
            glucoseRepository: dependencies.glucoseRepository,
            mealRepository: dependencies.mealRepository,
            service: dependencies.mealReviewService,
            settings: dependencies.mealReviewSettings,
            cache: dependencies.mealReviewCache
        ))
        self.dependencies = dependencies
        self.healthDataRevision = healthDataRevision
        self.onShowTab = onShowTab
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                glucoseCard
                mealsCard
                tipCard
                reviewCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("今天")
        .navigationSubtitle(Date.now.formatted(MealsDiaryView.subtitleStyle))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("拍照记录一餐", systemImage: "camera") { captureSource = .camera }
                    Button("从相册选择", systemImage: "photo.on.rectangle") { captureSource = .library }
                    Divider()
                    Button("记录血糖", systemImage: "drop") { glucoseEditor = .newReading }
                } label: {
                    Label("记录", systemImage: "plus")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("设置", systemImage: "person.crop.circle") {
                    isShowingSettings = true
                }
            }
        }
        .mealCapture(source: $captureSource, dependencies: dependencies) {
            reload()
        }
        .sheet(item: $glucoseEditor) { presentation in
            GlucoseEntryView(
                repository: dependencies.glucoseRepository,
                reading: presentation.reading
            ) {
                glucoseViewModel.load()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView(dependencies: dependencies)
            }
            .tint(Color.brandTeal)
        }
        .refreshable {
            reload()
            await reviewViewModel.load()
        }
        .task(id: healthDataRevision) {
            reload()
            await reviewViewModel.load()
        }
    }

    private func reload() {
        glucoseViewModel.load()
        mealViewModel.reload()
    }

    // MARK: 血糖

    private var glucoseCard: some View {
        SummaryCard(
            title: "血糖",
            systemImage: "drop.fill",
            tint: .glucoseTint,
            detail: glucoseDetail,
            showsChevron: true
        ) {
            glucoseContent
        }
        .tappableCard("查看血糖趋势") { onShowTab(.trends) }
    }

    private var glucoseDetail: String? {
        if let latest = glucoseViewModel.latestReading {
            return latest.measuredAt.formatted(GlucoMomentDateStyle.time)
        }
        if let previous = glucoseViewModel.previousReading {
            return previous.measuredAt.formatted(GlucoMomentDateStyle.monthDayTime)
        }
        return nil
    }

    @ViewBuilder
    private var glucoseContent: some View {
        if let latest = glucoseViewModel.latestReading {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    MetricValueText(value: DisplayFormat.glucose(latest.value), unit: "mmol/L")
                    Label(latest.state.phrase, systemImage: "circle.fill")
                        .labelStyle(StatusDotLabelStyle(tint: latest.state.tint))
                        .font(.footnote.weight(.medium))
                    if glucoseViewModel.readings.count > 1 {
                        Text(todaySummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if glucoseViewModel.readings.count > 1 {
                    GlucoseSparkline(readings: glucoseViewModel.readings, timeDomain: todayDomain)
                        .frame(width: 130, height: 64)
                }
            }
        } else if let previous = glucoseViewModel.previousReading {
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

    private var todaySummary: String {
        let summary = GlucoseMetricsCalculator.calculate(readings: glucoseViewModel.readings)
        let percentage = summary.inRangePercentage.map { " · \($0)% 在范围内" } ?? ""
        return "今天 \(summary.readingCount) 次\(percentage)"
    }

    private var todayDomain: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        return start...end
    }

    // MARK: 饮食

    private var mealsCard: some View {
        SummaryCard(
            title: "饮食",
            systemImage: "fork.knife",
            tint: .mealTint,
            detail: mealViewModel.meals.isEmpty ? nil : "\(mealViewModel.meals.count) 餐",
            showsChevron: true
        ) {
            mealsContent
        }
        .tappableCard("查看饮食记录") { onShowTab(.meals) }
    }

    @ViewBuilder
    private var mealsContent: some View {
        if mealViewModel.meals.isEmpty {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今天还没有记录")
                        .font(.headline)
                    Text("拍一张照片，看看这一餐的稳糖分")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("拍照", systemImage: "camera") { captureSource = .camera }
                    Button("从相册选择", systemImage: "photo.on.rectangle") { captureSource = .library }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.mealTint)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        MetricValueText(
                            value: DisplayFormat.whole(totalCalories),
                            unit: "千卡",
                            style: .title
                        )
                        Text("碳水 \(DisplayFormat.whole(totalCarbohydrates)) 克")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let averageScore {
                        VStack(spacing: 4) {
                            ScoreRing(score: averageScore, diameter: 48)
                            Text("平均稳糖分")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    ForEach(mealViewModel.meals.prefix(4)) { meal in
                        VStack(spacing: 6) {
                            MealPhotoThumbnail(
                                filename: meal.photoFilename,
                                photoStore: dependencies.mealPhotoStore,
                                size: 64,
                                cornerRadius: 16
                            )
                            .overlay(alignment: .bottomTrailing) {
                                if let score = meal.score {
                                    Text("\(score)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.stableScore(score), in: Capsule())
                                        .padding(4)
                                }
                            }
                            Text(meal.mealPeriod.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var totalCalories: Double {
        mealViewModel.meals.reduce(0) { $0 + $1.caloriesKcal }
    }

    private var totalCarbohydrates: Double {
        mealViewModel.meals.reduce(0) { $0 + $1.carbohydratesGrams }
    }

    private var averageScore: Int? {
        let scores = mealViewModel.meals.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    // MARK: 提示与复盘

    private var tipCard: some View {
        SummaryCard(
            title: mealViewModel.nextMealSuggestion == nil ? mealViewModel.currentGuidance.title : "下一餐提示",
            systemImage: "lightbulb.fill",
            tint: .brandAmber
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(mealViewModel.suggestionText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(mealViewModel.suggestionCitation)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var reviewCard: some View {
        switch reviewViewModel.state {
        case .loaded(let review, _, _):
            if let first = review.items.first {
                Button {
                    onShowTab(.trends)
                } label: {
                    SummaryCard(title: "近期复盘", systemImage: "sparkles", tint: .insightTint, showsChevron: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(first.text)
                                .font(.subheadline)
                                .lineLimit(3)
                            if review.items.count > 1 {
                                Text("还有 \(review.items.count - 1) 条")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        case .ready(let mealCount):
            Button {
                onShowTab(.trends)
            } label: {
                SummaryCard(title: "近期复盘", systemImage: "sparkles", tint: .insightTint, showsChevron: true) {
                    Text("最近有 \(mealCount) 餐带完整的餐后血糖，可以让 AI 帮你复盘了")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }
}

extension View {
    /// 整张卡片可点。用点按手势而不是 Button 包裹，卡片里的按钮仍能单独响应
    func tappableCard(_ accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        self
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: accessibilityLabel, action)
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
        TodayView(dependencies: dependencies, healthDataRevision: 0, onShowTab: { _ in })
    }
    .modelContainer(dependencies.modelContainer)
}
