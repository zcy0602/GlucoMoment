//
//  GlucoseTargetView.swift
//  GlucoMoment
//

import Charts
import SwiftUI

/// 血糖目标范围设置（sheet）。先选「我的情况」填入推荐值，再用滚轮按医嘱微调；
/// 顶部的示意图叠加最近 24 小时的真实读数，调节时能直接看到有多少落在范围内。
/// 「完成」才保存，「取消」放弃修改
struct GlucoseTargetView: View {
    let settings: GlucoseTargetSettings
    let repository: any GlucoseRepository

    @Environment(\.dismiss) private var dismiss
    @State private var population: GlucosePopulation?
    /// 以 0.1 mmol/L 为单位，避免小数比较的误差
    @State private var lowerTenths: Int
    @State private var upperTenths: Int
    @State private var recentReadings: [GlucoseReading] = []
    /// 已自定义时改选人群，先确认是否覆盖
    @State private var pendingPopulation: GlucosePopulation?

    init(settings: GlucoseTargetSettings, repository: any GlucoseRepository) {
        self.settings = settings
        self.repository = repository
        _population = State(initialValue: settings.population)
        _lowerTenths = State(initialValue: Self.tenths(settings.range.lowerBound))
        _upperTenths = State(initialValue: Self.tenths(settings.range.upperBound))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
                } footer: {
                    Text("目标范围会显示在各个图表上，并用于计算「目标范围内」的比例。请遵照医嘱调整。")
                }

                Section {
                    Picker("我的情况", selection: populationBinding) {
                        Text("未设置").tag(GlucosePopulation?.none)
                        ForEach(GlucosePopulation.allCases) { option in
                            Text(option.title).tag(Optional(option))
                        }
                    }
                } footer: {
                    Text("只用来填入推荐值，保存在这台 iPhone 上，不会发送给识别服务。")
                }

                Section {
                    boundPickers
                    recommendationRow
                } header: {
                    Text("目标范围（mmol/L）")
                } footer: {
                    Text("低于 \(DisplayFormat.glucose(GlucoseTargetRange.hypoglycemiaThreshold)) mmol/L 的读数仍按低血糖处理，不受这里的下限影响。老年人或容易发生低血糖的人，请和医生确认目标。")
                }
            }
            .navigationTitle("血糖目标范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        settings.save(population: population, range: draftRange)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "改为该人群的推荐值？",
                isPresented: isConfirmingPopulation,
                titleVisibility: .visible,
                presenting: pendingPopulation
            ) { option in
                Button("改为推荐值 \(Self.rangeText(option.recommendedRange))") {
                    applyRecommended(for: option)
                }
                Button("保留我的数值") {
                    population = option
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("你已经自定义了目标范围。")
            }
            .task { loadRecentReadings() }
        }
    }

    // MARK: 示意图

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                RectangleMark(
                    yStart: .value("下限", draftRange.lowerBound),
                    yEnd: .value("上限", draftRange.upperBound)
                )
                .foregroundStyle(Color.targetBandFill)

                ForEach(recentReadings) { reading in
                    LineMark(
                        x: .value("时间", reading.measuredAt),
                        y: .value("血糖", reading.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.glucoseTint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                boundRule(draftRange.upperBound, label: "上限", tint: GlucoseState.elevated.tint)
                boundRule(draftRange.lowerBound, label: "下限", tint: GlucoseState.low.tint)
            }
            .chartXScale(domain: timeDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(GlucoMomentDateStyle.time))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [3, 6, 9, 12])
            }
            .frame(height: 180)
            .animation(.smooth, value: draftRange)
            .accessibilityLabel("目标范围 \(Self.rangeText(draftRange)) mmol/L")

            Text(previewCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func boundRule(_ value: Double, label: String, tint: Color) -> some ChartContent {
        RuleMark(y: .value(label, value))
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                Text(DisplayFormat.glucose(value))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
    }

    private var previewCaption: String {
        guard !recentReadings.isEmpty else {
            return "最近 24 小时没有血糖读数。连接健康 App 同步连续血糖后，这里会叠加你自己的曲线。"
        }
        let inRange = recentReadings.count { draftRange.contains($0.value) }
        let percentage = Int((Double(inRange) / Double(recentReadings.count) * 100).rounded())
        return "最近 24 小时 \(recentReadings.count) 次读数，按这个范围有 \(percentage)% 在目标范围内。"
    }

    private var timeDomain: ClosedRange<Date> {
        let end = Date.now
        return end.addingTimeInterval(-86_400)...end
    }

    private var yDomain: ClosedRange<Double> {
        let values = recentReadings.map(\.value)
        let lower = min(2.0, (values.min() ?? 3) - 0.5)
        let upper = max(14.0, (values.max() ?? 12) + 0.8)
        return lower...upper
    }

    // MARK: 上下限

    private var boundPickers: some View {
        HStack(spacing: 0) {
            boundPicker(
                "下限",
                tint: GlucoseState.low.tint,
                selection: $lowerTenths,
                options: GlucoseTargetRange.lowerBoundOptions
            )
            boundPicker(
                "上限",
                tint: GlucoseState.elevated.tint,
                selection: $upperTenths,
                options: GlucoseTargetRange.upperBoundOptions
            )
        }
    }

    private func boundPicker(
        _ title: String,
        tint: Color,
        selection: Binding<Int>,
        options: [Double]
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { value in
                    Text(DisplayFormat.glucose(value))
                        .monospacedDigit()
                        .tag(Self.tenths(value))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            .clipped()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var recommendationRow: some View {
        let recommended = population?.recommendedRange ?? .standard
        if draftRange == recommended {
            Label {
                Text(population?.recommendationSource ?? "默认值，按国际 TIR 共识（2019）对糖尿病成人的推荐")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.brandTeal)
            }
        } else {
            HStack {
                Text("已自定义")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("恢复推荐值 \(Self.rangeText(recommended))") {
                    withAnimation(.smooth) { setDraft(recommended) }
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: 状态

    private var draftRange: GlucoseTargetRange {
        GlucoseTargetRange(lowerBound: Double(lowerTenths) / 10, upperBound: Double(upperTenths) / 10)
    }

    private var draftIsCustomized: Bool {
        draftRange != (population?.recommendedRange ?? .standard)
    }

    private var populationBinding: Binding<GlucosePopulation?> {
        Binding {
            population
        } set: { newValue in
            guard let newValue else {
                population = nil
                return
            }
            if draftIsCustomized, draftRange != newValue.recommendedRange {
                pendingPopulation = newValue
            } else {
                applyRecommended(for: newValue)
            }
        }
    }

    private var isConfirmingPopulation: Binding<Bool> {
        Binding {
            pendingPopulation != nil
        } set: { isPresented in
            if !isPresented { pendingPopulation = nil }
        }
    }

    private func applyRecommended(for option: GlucosePopulation) {
        population = option
        withAnimation(.smooth) { setDraft(option.recommendedRange) }
    }

    private func setDraft(_ range: GlucoseTargetRange) {
        lowerTenths = Self.tenths(range.lowerBound)
        upperTenths = Self.tenths(range.upperBound)
    }

    private func loadRecentReadings() {
        let end = Date.now
        let readings = (try? repository.readings(in: DateInterval(start: end.addingTimeInterval(-86_400), end: end))) ?? []
        recentReadings = readings.sorted { $0.measuredAt < $1.measuredAt }
    }

    private static func tenths(_ value: Double) -> Int {
        Int((value * 10).rounded())
    }

    private static func rangeText(_ range: GlucoseTargetRange) -> String {
        "\(DisplayFormat.glucose(range.lowerBound))–\(DisplayFormat.glucose(range.upperBound))"
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    GlucoseTargetView(
        settings: GlucoseTargetSettings(population: nil, range: .standard),
        repository: dependencies.glucoseRepository
    )
}
