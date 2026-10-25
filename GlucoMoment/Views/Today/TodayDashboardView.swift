//
//  TodayDashboardView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

struct TodayDashboardView: View {
    private let repository: any GlucoseRepository
    private let healthDataRevision: Int

    @State private var viewModel: TodayDashboardViewModel
    @State private var editorPresentation: GlucoseEditorPresentation?

    init(repository: any GlucoseRepository, healthDataRevision: Int = 0) {
        self.repository = repository
        self.healthDataRevision = healthDataRevision
        _viewModel = State(initialValue: TodayDashboardViewModel(repository: repository))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: viewModel.title) {
            if let snapshot = viewModel.currentSnapshot {
                NavigationLink {
                    GlucoseHistoryView(
                        repository: repository,
                        healthDataRevision: healthDataRevision
                    )
                } label: {
                    CurrentGlucoseCard(snapshot: snapshot, readings: Array(viewModel.compactReadings))
                }
                .buttonStyle(.plain)
            } else {
                NoGlucoseDataCard(
                    previousSnapshot: viewModel.previousSnapshot,
                    addAction: presentNewReading
                )
            }

            MetricsGrid(metrics: viewModel.metrics)
            NextActionCard(text: viewModel.nextAction)

            SectionHeader("今日记录", subtitle: viewModel.timelineSubtitle)
            if viewModel.readings.isEmpty {
                Text("点击右上角的加号手动记录，或在设置中连接健康 App。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.readings.reversed()) { reading in
                        GlucoseReadingRow(
                            reading: reading,
                            onEdit: reading.source == .manual
                                ? { editorPresentation = GlucoseEditorPresentation(reading: reading) }
                                : nil,
                            onDelete: reading.source == .manual
                                ? { Task { await viewModel.delete(reading) } }
                                : nil
                        )
                    }
                }
            }
        }
        .refreshable(action: viewModel.load)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    GlucoseHistoryView(
                        repository: repository,
                        healthDataRevision: healthDataRevision
                    )
                } label: {
                    Label("历史记录", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("glucose-history-link")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("记录血糖", systemImage: "plus", action: presentNewReading)
            }
        }
        .task(id: healthDataRevision) { viewModel.load() }
        .sheet(item: $editorPresentation) { presentation in
            GlucoseEntryView(
                repository: repository,
                reading: presentation.reading,
                onSaved: viewModel.load
            )
        }
        .alert("操作失败", isPresented: $viewModel.isShowingError) {
        } message: {
            Text(viewModel.errorMessage ?? "请稍后重试。")
        }
    }

    private func presentNewReading() {
        editorPresentation = .newReading
    }
}

private struct CurrentGlucoseCard: View {
    let snapshot: CurrentGlucoseSnapshot
    let readings: [GlucoseReading]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今日最新")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(snapshot.value)
                            .font(.largeTitle.bold())
                        Text(snapshot.unit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    PillTag(title: snapshot.stateLabel, tint: snapshot.stateTint)
                    Text(snapshot.measuredAt, format: GlucoMomentDateStyle.time)
                        .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "heart.text.square")
                        .font(.title)
                        .foregroundStyle(Color.brandTeal)
                        .frame(width: 48, height: 48)
                        .background(
                            Color.brandMint,
                            in: RoundedRectangle(cornerRadius: 16)
                        )

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }

            ReadingSparkBars(readings: readings)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(.secondarySystemGroupedBackground),
                Color.brandTeal.opacity(0.32)
            ]
        }

        return [.white, Color.brandMint.opacity(0.75)]
    }
}

private struct NoGlucoseDataCard: View {
    /// 今天之前最近的一条记录；为 nil 表示用户从未记录过血糖。
    let previousSnapshot: CurrentGlucoseSnapshot?
    let addAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(previousSnapshot == nil ? "开始记录血糖" : "今天还没测血糖", systemImage: "drop")
        } description: {
            VStack(spacing: 8) {
                Text(
                    previousSnapshot == nil
                        ? "记下第一条血糖，今日概览和趋势会随之生成。"
                        : "测一次并记录下来，就能看到今天的血糖概览。"
                )

                if let previousSnapshot {
                    HStack(spacing: 4) {
                        Text("上次记录")
                        Text(previousSnapshot.measuredAt, format: GlucoMomentDateStyle.monthDayTime)
                        Text("· \(previousSnapshot.value) \(previousSnapshot.unit)")
                    }
                    .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityElement(children: .combine)
                }
            }
        } actions: {
            Button("记录血糖", systemImage: "plus", action: addAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ReadingSparkBars: View {
    let readings: [GlucoseReading]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(readings) { reading in
                Capsule()
                    .fill(reading.state.tint)
                    .frame(width: 8, height: barHeight(for: reading.value))
                    .frame(maxWidth: .infinity, maxHeight: 92, alignment: .bottom)
                    .accessibilityLabel(
                        "\(reading.measuredAt.formatted(GlucoMomentDateStyle.time))，\(reading.value.formatted(.number.precision(.fractionLength(1)))) mmol/L，\(reading.state.label)"
                    )
                    .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
            }
        }
    }

    private func barHeight(for value: Double) -> CGFloat {
        let normalized = min(max((value - 2.0) / 13.0, 0), 1)
        return 28 + CGFloat(normalized) * 64
    }
}

private struct MetricsGrid: View {
    let metrics: [DashboardMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(metrics) { metric in
                MetricCard(metric: metric)
            }
        }
    }
}

private struct NextActionCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.brandTeal, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text("下一步")
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct GlucoseReadingRow: View {
    let reading: GlucoseReading
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var isConfirmingDeletion = false

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(reading.state.tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(reading.measuredAt, format: GlucoMomentDateStyle.time)
                    .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(reading.source.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = reading.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Text("\(reading.value.formatted(.number.precision(.fractionLength(1)))) mmol/L")
                .font(.subheadline.weight(.semibold))

            if let onEdit, onDelete != nil {
                Menu("记录操作", systemImage: "ellipsis.circle") {
                    Button("编辑", systemImage: "pencil", action: onEdit)
                    Button("删除", systemImage: "trash", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                }
                .labelStyle(.iconOnly)
                .confirmationDialog("删除这条血糖记录？", isPresented: $isConfirmingDeletion) {
                    if let onDelete {
                        Button("删除记录", role: .destructive, action: onDelete)
                    }
                }
            } else {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(Color.brandTeal)
                    .accessibilityLabel("由健康 App 管理")
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        TodayDashboardView(repository: dependencies.glucoseRepository)
    }
    .modelContainer(dependencies.modelContainer)
}
