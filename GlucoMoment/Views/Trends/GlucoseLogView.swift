//
//  GlucoseLogView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 最近 30 天的所有血糖读数，按天分组。手动记录可以左滑删除、点按修改；健康 App 的记录只读
struct GlucoseLogView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: GlucoseLogViewModel
    @State private var editor: GlucoseEditorPresentation?

    init(dependencies: AppDependencies, healthDataRevision: Int) {
        _viewModel = State(initialValue: GlucoseLogViewModel(repository: dependencies.glucoseRepository))
        self.dependencies = dependencies
        self.healthDataRevision = healthDataRevision
    }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.dayGroups) { group in
                Section {
                    ForEach(group.readings) { reading in
                        row(reading)
                    }
                } header: {
                    Text(group.day.formatted(MealsDiaryView.subtitleStyle))
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.readings.isEmpty, viewModel.errorMessage == nil {
                ContentUnavailableView(
                    "最近 \(GlucoseLogViewModel.dayCount) 天没有血糖记录",
                    systemImage: "drop",
                    description: Text("点右上角的加号手动记录。")
                )
            }
        }
        .navigationTitle("血糖记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("记录血糖", systemImage: "plus") { editor = .newReading }
            }
        }
        .sheet(item: $editor) { presentation in
            GlucoseEntryView(repository: dependencies.glucoseRepository, reading: presentation.reading) {
                viewModel.load()
            }
        }
        .task(id: healthDataRevision) { viewModel.load() }
    }

    @ViewBuilder
    private func row(_ reading: GlucoseReading) -> some View {
        let content = HStack(spacing: 12) {
            Circle()
                .fill(reading.state.tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(DisplayFormat.glucose(reading.value))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("mmol/L")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = reading.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if reading.source == .healthKit {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .accessibilityLabel("来自健康 App")
            }
            Text(reading.measuredAt.formatted(GlucoMomentDateStyle.time))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }

        if reading.source == .manual {
            Button {
                editor = GlucoseEditorPresentation(reading: reading)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button("删除", systemImage: "trash", role: .destructive) {
                    Task { await viewModel.delete(reading) }
                }
            }
        } else {
            content
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        GlucoseLogView(dependencies: dependencies, healthDataRevision: 0)
    }
    .modelContainer(dependencies.modelContainer)
}
