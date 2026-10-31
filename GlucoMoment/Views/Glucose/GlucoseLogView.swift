//
//  GlucoseLogView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 血糖记录：一次看一天，顶部可以切换日期。手动记录可以左滑删除、点按修改；健康 App 的记录只读
struct GlucoseLogView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: GlucoseLogViewModel
    @State private var editor: GlucoseEditorPresentation?
    @State private var isShowingDayPicker = false

    /// `initialDay` 为 nil 时从今天开始
    init(dependencies: AppDependencies, healthDataRevision: Int, initialDay: Date? = nil) {
        _viewModel = State(initialValue: GlucoseLogViewModel(
            repository: dependencies.glucoseRepository,
            initialDay: initialDay
        ))
        self.dependencies = dependencies
        self.healthDataRevision = healthDataRevision
    }

    var body: some View {
        List {
            Section {
                DateNavigatorBar(
                    title: viewModel.selectedDay.formatted(MealsDiaryView.subtitleStyle),
                    pageLabel: "一天",
                    isShowingToday: viewModel.isShowingToday,
                    canGoBack: viewModel.canGoBack,
                    canGoForward: viewModel.canGoForward,
                    onTapTitle: { isShowingDayPicker = true },
                    onToday: viewModel.showToday,
                    onPrevious: viewModel.showPrevious,
                    onNext: viewModel.showNext
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.readings.isEmpty {
                // 放在列表里而不是 overlay：overlay 会盖住上面的日期行，点不到
                Section {
                    ContentUnavailableView(
                        "这一天没有血糖记录",
                        systemImage: "drop",
                        description: Text(emptyDescription)
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(viewModel.readings) { reading in
                        row(reading)
                    }
                } header: {
                    Text("\(viewModel.readings.count) 次读数")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
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
        .sheet(isPresented: $isShowingDayPicker) {
            DayPickerSheet(
                selectedDate: viewModel.selectedDay,
                range: viewModel.earliestDay...viewModel.today
            ) { day in
                viewModel.select(day: day)
            }
        }
        .onChange(of: viewModel.selectedDay) {
            withAnimation(.smooth) { viewModel.load() }
        }
        .task(id: healthDataRevision) { viewModel.load() }
    }

    private var emptyDescription: String {
        viewModel.isShowingToday
            ? "点右上角的加号手动记录。"
            : "健康 App 每次同步最近 30 天，更早的记录只有之前同步过的才会保留。"
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
