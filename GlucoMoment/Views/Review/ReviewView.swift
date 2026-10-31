//
//  ReviewView.swift
//  GlucoMoment
//

import Charts
import SwiftData
import SwiftUI

/// 「复盘」标签页：把每一餐吃了什么和吃完血糖怎么变放在一起看。
/// 从上到下是概览、AI 复盘、稳糖分与实测升幅的对照、每一餐的餐后反应，最后是计算方法
struct ReviewView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: MealResponseOverviewViewModel
    @State private var reviewViewModel: MealReviewViewModel
    @State private var isShowingReviewConsent = false
    /// 餐后反应列表是否展开全部；不保存，每次进来都是折叠的
    @State private var isShowingAllMeals = false

    /// 餐后反应列表折叠时显示的条数
    private static let collapsedMealCount = 5

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
                // 整页都按同一个时间范围统计，只在第一节写一次
                CardSectionTitle("概览", trailing: "最近 \(MealResponseOverviewViewModel.reviewDays) 天")

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardBackground()
                }

                overviewCard

                // 先给结论，下面的散点图和每餐列表是依据
                CardSectionTitle("AI 复盘")
                MealReviewInsightCard(viewModel: reviewViewModel) {
                    isShowingReviewConsent = true
                }

                CardSectionTitle("稳糖分与实测升幅")
                comparisonCard

                CardSectionTitle(
                    "餐后反应",
                    trailing: viewModel.entries.isEmpty ? nil : "共 \(viewModel.entries.count) 餐"
                )
                if !viewModel.entries.isEmpty {
                    Picker("排序", selection: $viewModel.sortOrder) {
                        ForEach(MealResponseOverviewViewModel.SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                mealsCard

                methodCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("复盘")
        // 大标题和右上角按钮同一行，与 App Store、音乐一致
        .toolbarTitleDisplayMode(.inlineLarge)
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

    // MARK: 餐后反应

    @ViewBuilder
    private var mealsCard: some View {
        let allEntries = viewModel.sortedEntries
        // 先排序再截取，折叠时看到的是「最近 5 餐」或「升得最多的 5 餐」
        let isCollapsible = allEntries.count > Self.collapsedMealCount
        let entries = isCollapsible && !isShowingAllMeals
            ? Array(allEntries.prefix(Self.collapsedMealCount))
            : allEntries
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

                if isCollapsible {
                    Divider()
                        .padding(.vertical, 8)
                    Button {
                        withAnimation(.snappy) {
                            isShowingAllMeals.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isShowingAllMeals ? "收起" : "显示全部 \(allEntries.count) 餐")
                            Image(systemName: isShowingAllMeals ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
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
                .foregroundStyle(GlucoseTargetRange.current.curveGradient(yDomain: yDomain))
                .alignsMarkStylesWithPlotArea()
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

/// AI 复盘卡片：按 `MealReviewViewModel.State` 显示开启引导、进度、生成按钮或结果；
/// 结果下方是重新生成按钮（有新的餐时附提示）和历史复盘入口
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
                largeButton("生成复盘", systemImage: "sparkles") {
                    Task { await viewModel.generate() }
                }

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
                largeButton("重试", systemImage: "arrow.clockwise") {
                    Task { await viewModel.load() }
                }
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
        MealReviewItemsView(review: review)

        Text(serviceError == nil ? review.originText : "AI 暂时不可用，以下由本机模板生成")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

        // 有新的餐时在按钮上方说明为什么值得重新生成；餐不够时按钮变灰并写明原因
        if viewModel.newMealCount > 0, viewModel.canGenerate {
            Label("又有 \(viewModel.newMealCount) 餐新的餐后血糖，可以重新生成", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Color.insightTint)
        } else if !viewModel.canGenerate {
            Text("最近 \(MealReviewPayloadBuilder.reviewDays) 天带完整餐后血糖的餐不足 \(MealReviewViewModel.minimumMealCount) 餐，暂时不能重新生成")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        largeButton("重新生成", systemImage: "arrow.clockwise") {
            Task { await viewModel.generate() }
        }
        .disabled(!viewModel.canGenerate)

        VStack(alignment: .leading, spacing: 2) {
            Text(coverage(generatedAt: generatedAt))
            Text("仅供参考，不是诊断。调整饮食或用药请咨询医生。")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)

        if !viewModel.history.isEmpty {
            Divider()
            NavigationLink {
                MealReviewHistoryView(viewModel: viewModel)
            } label: {
                HStack {
                    Label("历史复盘", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(viewModel.history.count) 份")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 卡片里的主要操作：生成、重新生成、重试都用同一种大按钮
    private func largeButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(.insightTint)
        .controlSize(.large)
    }

    /// 例如「根据 10/18–11/1 的 12 餐 · 生成于 11月1日 14:30」；本地模板没有保存，只写生成时间
    private func coverage(generatedAt: Date) -> String {
        let generated = "生成于 \(generatedAt.formatted(GlucoMomentDateStyle.monthDayTime))"
        guard let saved = viewModel.shownReview, let range = saved.coverageText else { return generated }
        return "\(range) · \(generated)"
    }
}

/// 复盘的安全提醒和逐条内容，卡片和历史详情共用
struct MealReviewItemsView: View {
    let review: MealReview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        }
    }
}

extension MealReview {
    /// 结果卡底部说明这份复盘由谁写
    var originText: String {
        isFallback ? "AI 的结果未通过校验，以下由本机模板生成" : "AI 撰写 · 数字由本机计算"
    }
}

extension SavedMealReview {
    /// 例如「根据 10/18–11/1 的 12 餐」；从旧版缓存迁移来的记录没有用餐时间，只写餐数
    var coverageText: String? {
        let count = mealCount > 0 ? "的 \(mealCount) 餐" : ""
        guard let firstMealAt, let lastMealAt else {
            return mealCount > 0 ? "根据 \(mealCount) 餐" : nil
        }
        let first = firstMealAt.formatted(GlucoMomentDateStyle.numericMonthDay)
        let last = lastMealAt.formatted(GlucoMomentDateStyle.numericMonthDay)
        return "根据 \(first == last ? first : "\(first)–\(last)")\(count)"
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        ReviewView(dependencies: dependencies, healthDataRevision: 0)
    }
    .modelContainer(dependencies.modelContainer)
}
