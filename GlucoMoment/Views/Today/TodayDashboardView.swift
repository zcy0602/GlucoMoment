//
//  TodayDashboardView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

struct TodayDashboardView: View {
    private let repository: any GlucoseRepository

    @State private var viewModel: TodayDashboardViewModel
    @State private var editorPresentation: GlucoseEditorPresentation?

    init(repository: any GlucoseRepository) {
        self.repository = repository
        _viewModel = State(initialValue: TodayDashboardViewModel(repository: repository))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: viewModel.title) {
            if let snapshot = viewModel.currentSnapshot {
                CurrentGlucoseCard(snapshot: snapshot, readings: Array(viewModel.compactReadings))
            } else {
                NoGlucoseDataCard(addAction: presentNewReading)
            }

            MetricsGrid(metrics: viewModel.metrics)
            NextActionCard(text: viewModel.nextAction)

            SectionHeader("今日记录", subtitle: viewModel.timelineSubtitle)
            if viewModel.readings.isEmpty {
                Text("点击右上角的加号，记录第一条血糖。")
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
                            onEdit: { editorPresentation = GlucoseEditorPresentation(reading: reading) },
                            onDelete: { viewModel.delete(reading) }
                        )
                    }
                }
            }
        }
        .refreshable(action: viewModel.load)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("记录血糖", systemImage: "plus", action: presentNewReading)
            }
        }
        .task(viewModel.load)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最新记录")
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
                    Text(snapshot.measuredAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "heart.text.square")
                    .font(.title)
                    .foregroundStyle(Color.brandTeal)
                    .frame(width: 48, height: 48)
                    .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 16))
            }

            ReadingSparkBars(readings: readings)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.white, Color.brandMint.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

private struct NoGlucoseDataCard: View {
    let addAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("还没有血糖记录", systemImage: "drop")
        } description: {
            Text("先记录一条血糖数据，今日概览和趋势会自动更新。")
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
                        "\(reading.measuredAt.formatted(.dateTime.hour().minute()))，\(reading.value.formatted(.number.precision(.fractionLength(1)))) mmol/L，\(reading.state.label)"
                    )
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

private struct GlucoseReadingRow: View {
    let reading: GlucoseReading
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDeletion = false

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(reading.state.tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(reading.measuredAt, format: .dateTime.hour().minute())
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

            Menu("记录操作", systemImage: "ellipsis.circle") {
                Button("编辑", systemImage: "pencil", action: onEdit)
                Button("删除", systemImage: "trash", role: .destructive) {
                    isConfirmingDeletion = true
                }
            }
            .labelStyle(.iconOnly)
            .confirmationDialog("删除这条血糖记录？", isPresented: $isConfirmingDeletion) {
                Button("删除记录", role: .destructive, action: onDelete)
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
