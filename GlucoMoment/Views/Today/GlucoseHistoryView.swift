//
//  GlucoseHistoryView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

struct GlucoseHistoryView: View {
    private let healthDataRevision: Int
    @State private var viewModel: GlucoseHistoryViewModel

    init(repository: any GlucoseRepository, healthDataRevision: Int = 0) {
        self.healthDataRevision = healthDataRevision
        _viewModel = State(
            initialValue: GlucoseHistoryViewModel(repository: repository)
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: "血糖历史") {
            HistoryDateSelector(selectedDate: $viewModel.selectedDate)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(viewModel.metrics) { metric in
                    MetricCard(metric: metric)
                }
            }

            SectionHeader("血糖记录", subtitle: viewModel.recordSubtitle)

            if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "暂时无法读取历史记录",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if viewModel.readings.isEmpty {
                ContentUnavailableView(
                    "当天没有血糖记录",
                    systemImage: "drop",
                    description: Text("可以切换日期继续查询。")
                )
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.readings.reversed()) { reading in
                        GlucoseReadingRow(
                            reading: reading,
                            onEdit: nil,
                            onDelete: nil
                        )
                    }
                }
            }
        }
        .refreshable(action: viewModel.load)
        .task(id: "\(viewModel.selectedDate.timeIntervalSinceReferenceDate)-\(healthDataRevision)") {
            viewModel.load()
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        GlucoseHistoryView(repository: dependencies.glucoseRepository)
    }
    .modelContainer(dependencies.modelContainer)
}
