//
//  ReviewView.swift
//  GlucoMoment
//

import Charts
import SwiftData
import SwiftUI

/// 「复盘」标签页：把每一餐吃了什么和吃完血糖怎么变放在一起看。
/// 从上到下是概览、稳糖分与实测升幅的对照、每一餐的餐后反应、AI 复盘，最后是计算方法
struct ReviewView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: MealResponseOverviewViewModel
    @State private var reviewViewModel: MealReviewViewModel
    @State private var isShowingReviewConsent = false

    init(dependencies: AppDependencies, healthDataRevision: Int) {
        _viewModel = State(initialValue: MealResponseOverviewViewModel(
            glucoseRepository: dependencies.glucoseRepository,
            mealRepository: dependencies.mealRepository
        ))
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
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardBackground()
                }

                overviewCard

                CardSectionTitle("稳糖分与实测升幅")
                comparisonCard

                CardSectionTitle("每一餐", trailing: "最近 \(MealResponseOverviewViewModel.reviewDays) 天")
                if !viewModel.entries.isEmpty {
                    Picker("排序", selection: $viewModel.sortOrder) {
                        ForEach(MealResponseOverviewViewModel.SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                mealsCard

                CardSectionTitle("AI 复盘", trailing: "最近 \(MealReviewPayloadBuilder.reviewDays) 天")
                MealReviewInsightCard(viewModel: reviewViewModel) {
                    isShowingReviewConsent = true
                }

                methodCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("复盘")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(dependencies: dependencies)
            }
        }
        .sheet(isPresented: $isShowingReviewConsent) {
            MealReviewConsentView(destination: dependencies.foodAnalysisSettings.reviewDestinationDescription) {
                Task { await reviewViewModel.enable() }
            }
        }
        .onChange(of: dependencies.mealReviewSettings.isEnabled) {
            Task { await reviewViewModel.load() }
        }
        .refreshable {
            await dependencies.healthKitCoordinator.refresh()
            await reload()
        }
        .task(id: healthDataRevision) {
            await reload()
        }
        // 标签页切换时视图不会重建；回到这一页时按最新记录刷新（在饮食页新记的餐要出现在这里）
        .onAppear {
            Task { await reload() }
        }
    }

    private func reload() async {
        viewModel.load()
        await reviewViewModel.load()
    }

    // MARK: 概览

    private var overviewCard: some View {
        HStack(spacing: 0) {
            overviewColumn(title: "有餐后血糖") {
                overviewNumber("\(viewModel.respondedEntries.count)", unit: "/ \(viewModel.entries.count) 餐")
            }
            Divider().frame(height: 40)
            overviewColumn(title: "平均升幅") {
                overviewNumber(
                    viewModel.averagePeakRise.map(DisplayFormat.glucoseChange) ?? "—",
                    unit: "mmol/L",
                    tint: .glucoseTint
                )
            }
            Divider().frame(height: 40)
            overviewColumn(title: "平均稳糖分") {
                ScoreRing(score: viewModel.averageScore, diameter: 44)
            }
        }
        .padding(.vertical, 4)
        .cardBackground()
    }

    private func overviewColumn<Value: View>(title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 6) {
            value()
                .frame(height: 44)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func overviewNumber(_ value: String, unit: String, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 4)
    }

    // MARK: 稳糖分与实测升幅

    @ViewBuilder
    private var comparisonCard: some View {
        let entries = viewModel.comparisonEntries
        VStack(alignment: .leading, spacing: 12) {
            if entries.count >= 2 {
                ScoreRiseChart(entries: entries)
                    .frame(height: 220)
                Text("每个点是一餐。按公式，稳糖分越高的餐，餐后升幅应该越小；看看你自己的实测是不是这样。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(systemImage: "chart.dots.scatter", tint: .glucoseTint, size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entries.isEmpty ? "还没有可以对照的餐" : "再记一餐就能对照了")
                            .font(.headline)
                        Text("稳糖分是吃之前按公式算的，餐后升幅是连续血糖仪实测的。拍照记录每一餐，并让连续血糖仪同步到健康 App，这里会把两者放在一起，看看分数准不准。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .cardBackground()
    }

    // MARK: 每一餐

    @ViewBuilder
    private var mealsCard: some View {
        let entries = viewModel.sortedEntries
        if entries.isEmpty {
            ContentUnavailableView {
                Label("最近 \(MealResponseOverviewViewModel.reviewDays) 天没有饮食记录", systemImage: "fork.knife")
            } description: {
                Text("在「饮食」页拍照记录一餐，这里会显示它的稳糖分和餐后血糖。")
            }
            .frame(maxWidth: .infinity)
            .cardBackground(padding: 8)
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    NavigationLink {
                        MealDetailView(meal: entry.meal, dependencies: dependencies) {
                            Task { await reload() }
                        }
                    } label: {
                        MealResponseRow(entry: entry, photoStore: dependencies.mealPhotoStore)
                    }
                    .buttonStyle(.plain)

                    if entry.id != entries.last?.id {
                        Divider()
                            .padding(.leading, 60)
                            .padding(.vertical, 8)
                    }
                }
            }
            .cardBackground()
        }
    }

    // MARK: 计算方法

    private var methodCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ScoreMethodView()
            } label: {
                HStack {
                    Label("稳糖分怎么算", systemImage: "function")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.vertical, 12)

            DisclosureGroup {
                Text("以开始用餐前 15 分钟的平均血糖为基线，取开始后 2 小时内的最高值减去基线，就是最高升幅。如果记录时血糖已经在上升，会把开始时间往前调到上升前的最低点；1 小时内吃过上一餐时不调整。2 小时内又吃了下一餐时：下一餐前血糖已经回落，只算前一个峰；还在同一个峰上，就当作连着吃，升幅是几餐一起的。需要连续血糖仪的数据，2 小时内至少有 \(MealGlucoseResponseCalculator.minimumWindowReadings) 条读数。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } label: {
                Label("餐后升幅怎么算", systemImage: "waveform.path.ecg")
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
        }
        .cardBackground()
    }
}

/// 横轴稳糖分、纵轴实测最高升幅的散点图，点的颜色和稳糖分圆环一致
private struct ScoreRiseChart: View {
    let entries: [MealResponseOverviewViewModel.Entry]

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                if let score = entry.meal.score, let response = entry.response {
                    PointMark(
                        x: .value("稳糖分", score),
                        y: .value("升幅", response.peakRise)
                    )
                    .foregroundStyle(Color.stableScore(score))
                    .symbolSize(80)
                    .accessibilityLabel(entry.meal.title)
                    .accessibilityValue("稳糖分 \(score)，升幅 \(DisplayFormat.glucoseChange(response.peakRise)) mmol/L")
                }
            }
        }
        .chartXScale(domain: 0...100)
        .chartYScale(domain: yDomain)
        .chartXAxisLabel("稳糖分", alignment: .trailing)
        .chartYAxisLabel("最高升幅 mmol/L")
    }

    private var yDomain: ClosedRange<Double> {
        let rises = entries.compactMap { $0.response?.peakRise }
        let lower = min(0, (rises.min() ?? 0) - 0.5)
        let upper = max(4, (rises.max() ?? 0) + 0.5)
        return lower...upper
    }
}

/// 复盘列表的一行：缩略图、名称、时间，右侧是餐后小曲线和升幅，最右是稳糖分
private struct MealResponseRow: View {
    let entry: MealResponseOverviewViewModel.Entry
    let photoStore: any MealPhotoStoring

    private var meal: MealRecord { entry.meal }

    var body: some View {
        HStack(spacing: 12) {
            MealPhotoThumbnail(filename: meal.photoFilename, photoStore: photoStore, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(meal.eatenAt.formatted(GlucoMomentDateStyle.monthDayTime)) · \(meal.mealPeriod.rawValue)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let response = entry.response {
                VStack(alignment: .trailing, spacing: 2) {
                    PostMealSparkline(response: response)
                        .frame(width: 64, height: 26)
                    Text("\(DisplayFormat.glucoseChange(response.peakRise)) mmol/L")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(response.hasLowReading ? GlucoseState.low.tint : Color.glucoseTint)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("最高升幅 \(DisplayFormat.glucoseChange(response.peakRise)) mmol/L")
            } else {
                Text("暂无餐后血糖")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScoreRing(score: meal.score, diameter: 34)
        }
        .contentShape(Rectangle())
    }
}

/// 一餐前后的小曲线（开始前 45 分钟到开始后 180 分钟），虚线是基线
private struct PostMealSparkline: View {
    let response: MealGlucoseResponse

    private var points: [(minutes: Int, value: Double)] {
        zip(MealGlucoseResponseCalculator.curveOffsets, response.curve).compactMap { offset, value in
            value.map { (offset, $0) }
        }
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("基线", response.baseline))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

            ForEach(points, id: \.minutes) { point in
                LineMark(
                    x: .value("分钟", point.minutes),
                    y: .value("血糖", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.glucoseTint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: (MealGlucoseResponseCalculator.curveOffsets.first ?? -45)...(MealGlucoseResponseCalculator.curveOffsets.last ?? 180))
        .chartYScale(domain: yDomain)
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value) + [response.baseline]
        let lower = (values.min() ?? 4) - 0.3
        let upper = max((values.max() ?? 8) + 0.3, lower + 2)
        return lower...upper
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
        ReviewView(dependencies: dependencies, healthDataRevision: 0)
    }
    .modelContainer(dependencies.modelContainer)
}
