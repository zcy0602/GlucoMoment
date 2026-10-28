//
//  MealDetailView.swift
//  GlucoMoment
//

import Charts
import SwiftUI

/// 已保存餐食的详情。与识别结果页同一套版式，点「编辑」可修改；多了一张「餐后血糖」卡，
/// 用连续血糖数据画出这一餐前后的曲线——这是「看懂每一餐」最直接的证据
struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MealDetailViewModel
    @State private var isShowingBreakdown = false
    @State private var isConfirmingDelete = false
    @State private var isEditing = false
    private let dependencies: AppDependencies
    private let onChanged: () -> Void

    /// `onChanged` 在删除或编辑保存后调用，供列表刷新
    init(meal: MealRecord, dependencies: AppDependencies, onChanged: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: MealDetailViewModel(
            meal: meal,
            glucoseRepository: dependencies.glucoseRepository,
            mealRepository: dependencies.mealRepository,
            photoStore: dependencies.mealPhotoStore
        ))
        self.dependencies = dependencies
        self.onChanged = onChanged
    }

    private var meal: MealRecord { viewModel.meal }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !viewModel.photos.isEmpty {
                    MealPhotoHeader(photos: viewModel.photos)
                }

                header

                StableScoreSummaryCard(
                    score: meal.score,
                    breakdown: meal.stableScore,
                    fallbackImpact: meal.glucoseImpact
                ) {
                    isShowingBreakdown = true
                }

                NutritionStrip(
                    caloriesKcal: meal.caloriesKcal,
                    carbohydratesGrams: meal.carbohydratesGrams,
                    proteinGrams: meal.proteinGrams,
                    fatGrams: meal.fatGrams
                )
                .cardBackground(padding: 14)

                PostMealGlucoseCard(
                    eatenAt: meal.eatenAt,
                    points: viewModel.glucosePoints,
                    response: viewModel.response
                )

                if !meal.items.isEmpty {
                    foodsCard
                }

                if let notes = notesText {
                    SummaryCard(title: "我的补充", systemImage: "text.bubble", tint: .secondary) {
                        Text(notes)
                            .font(.subheadline)
                    }
                }

                if !meal.suggestions.isEmpty {
                    MealSuggestionsCard(
                        suggestions: meal.suggestions,
                        // 条目都有类别时，保存的是按规则生成的建议
                        citation: meal.stableScore == nil ? nil : DietGuideline.sourceCitation
                    )
                }

                analysisInfo

                MealDisclaimerFooter()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(meal.mealPeriod.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { isEditing = true }
                }
            }
            if viewModel.canDelete {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("删除这条记录", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis")
                    }
                }
            }
        }
        .confirmationDialog("删除这条记录？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { delete() }
        } message: {
            Text("照片和识别结果会一起删除，健康 App 中对应的营养记录也会移除。")
        }
        .sheet(isPresented: $isShowingBreakdown) {
            ScoreBreakdownView(score: meal.score, breakdown: meal.stableScore)
        }
        .sheet(isPresented: $isEditing) {
            MealEditView(meal: meal, photos: viewModel.photos, dependencies: dependencies) { updated in
                viewModel.replace(with: updated)
                onChanged()
            }
        }
        // 编辑后用餐时间可能变了，按整条记录重新加载餐后血糖
        .task(id: meal) {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meal.title)
                .font(.title2.weight(.bold))
            HStack(spacing: 6) {
                Text(meal.eatenAt, format: GlucoMomentDateStyle.fullDateTime)
                if meal.source == .healthKit {
                    Text("·")
                    Label("来自健康 App", systemImage: "heart.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var foodsCard: some View {
        SummaryCard(title: "食物", systemImage: "fork.knife", tint: .mealTint, detail: "\(meal.items.count) 样") {
            VStack(spacing: 0) {
                ForEach(meal.items) { item in
                    FoodItemRow(
                        name: item.name,
                        category: item.foodCategory,
                        portionDescription: item.portionDescription,
                        estimatedGrams: item.estimatedGrams,
                        carbohydratesGrams: item.carbohydratesGrams
                    )
                    if item.id != meal.items.last?.id {
                        Divider()
                            .padding(.leading, 22)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var notesText: String? {
        let parts = [meal.userFoodContext, meal.note]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    @ViewBuilder
    private var analysisInfo: some View {
        if meal.source == .aiPhoto {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    if let provider = meal.aiProvider {
                        LabeledContent("识别服务", value: provider)
                    }
                    if let model = meal.aiModel {
                        LabeledContent("模型", value: model)
                    }
                    if let confidence = meal.analysisConfidence {
                        LabeledContent("识别把握", value: confidence.formatted(.percent.precision(.fractionLength(0))))
                    }
                    let confirmations = meal.uncertainties + meal.followUpQuestions
                    if !confirmations.isEmpty {
                        Text(confirmations.joined(separator: "\n"))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .font(.footnote)
                .padding(.top, 8)
            } label: {
                Text("识别信息")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.secondary)
            .cardBackground()
        }
    }

    private func delete() {
        Task {
            guard await viewModel.delete() else { return }
            onChanged()
            dismiss()
        }
    }
}

/// 一餐前后的血糖曲线：横轴是相对用餐的分钟数，标出基线和峰值
struct PostMealGlucoseCard: View {
    let eatenAt: Date
    let points: [GlucosePoint]
    let response: MealGlucoseResponse?

    private var start: Date { response?.start ?? eatenAt }

    var body: some View {
        SummaryCard(title: "餐后血糖", systemImage: "waveform.path.ecg", tint: .glucoseTint, detail: detail) {
            if points.count >= 3 {
                VStack(alignment: .leading, spacing: 14) {
                    if let response {
                        HStack(spacing: 0) {
                            stat(DisplayFormat.glucoseChange(response.peakRise), unit: "mmol/L", title: "最高升幅")
                            stat(DisplayFormat.whole(response.peakMinutes), unit: "分钟", title: "到达峰值")
                            stat(response.rise2h.map(DisplayFormat.glucoseChange) ?? "—", unit: "mmol/L", title: "2 小时")
                        }
                    }
                    chart
                        .frame(height: 170)
                    if let response, response.startShiftMinutes > 0 {
                        Text("血糖在记录时间前 \(response.startShiftMinutes) 分钟已开始上升，按实际开始时间计算。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("没有这段时间的连续血糖数据。佩戴连续血糖仪并同步到健康 App 后，这里会显示这一餐前后的血糖曲线。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String? {
        guard points.count >= 3 else { return nil }
        return response == nil ? "数据不完整" : "用餐前后"
    }

    private func stat(_ value: String, unit: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func minutes(_ date: Date) -> Double {
        date.timeIntervalSince(start) / 60
    }

    private var chart: some View {
        Chart {
            RectangleMark(
                yStart: .value("下限", GlucoseTargetRange.standard.lowerBound),
                yEnd: .value("上限", GlucoseTargetRange.standard.upperBound)
            )
            .foregroundStyle(Color.targetBandFill)

            ForEach(points, id: \.time) { point in
                LineMark(
                    x: .value("分钟", minutes(point.time)),
                    y: .value("血糖", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.glucoseTint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            RuleMark(x: .value("用餐", 0.0))
                .foregroundStyle(Color.mealTint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Label("用餐", systemImage: "fork.knife")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.mealTint)
                }

            if let response {
                RuleMark(y: .value("基线", response.baseline))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                PointMark(
                    x: .value("分钟", response.peakMinutes),
                    y: .value("血糖", response.peak)
                )
                .foregroundStyle(Color.glucoseTint)
                .symbolSize(60)
                .annotation(position: .top, spacing: 4) {
                    Text(DisplayFormat.glucose(response.peak))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.glucoseTint)
                }
            }
        }
        .chartXScale(domain: -60...180)
        .chartXAxis {
            AxisMarks(values: [-60, 0, 60, 120, 180]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minute = value.as(Double.self) {
                        Text(minute == 0 ? "0" : "\(Int(minute))′")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4))
        }
        .chartYScale(domain: yDomain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let lower = min(3.0, (values.min() ?? 4) - 0.5)
        let upper = max(11.0, (values.max() ?? 10) + 0.5)
        return lower...upper
    }

    private var accessibilitySummary: String {
        guard let response else { return "这一餐前后的血糖曲线" }
        return "餐后血糖最高升高 \(DisplayFormat.glucose(response.peakRise)) mmol/L，第 \(DisplayFormat.whole(response.peakMinutes)) 分钟达到峰值"
    }
}

#Preview("有餐后数据") {
    let start = Date.now.addingTimeInterval(-4 * 3_600)
    let values: [Double] = [5.4, 5.5, 5.3, 5.4, 5.6, 6.2, 7.1, 7.9, 8.4, 8.3, 7.8, 7.1, 6.6, 6.2, 5.9, 5.8, 5.6, 5.5, 5.5]
    let points = values.enumerated().map { index, value in
        GlucosePoint(time: start.addingTimeInterval(Double(index - 4) * 15 * 60), value: value)
    }
    let dense = stride(from: 0, to: points.count - 1, by: 1).flatMap { index -> [GlucosePoint] in
        let a = points[index], b = points[index + 1]
        return (0..<3).map { step in
            let fraction = Double(step) / 3
            return GlucosePoint(time: a.time.addingTimeInterval(fraction * 15 * 60), value: a.value + (b.value - a.value) * fraction)
        }
    }
    ScrollView {
        PostMealGlucoseCard(
            eatenAt: start,
            points: dense,
            response: MealGlucoseResponseCalculator.response(recordedStart: start, points: dense)
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
