//
//  MealHistoryView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

struct MealHistoryView: View {
    private let photoStore: any MealPhotoStoring
    private let healthDataRevision: Int
    @State private var viewModel: MealHistoryViewModel

    init(
        repository: any MealRepository,
        photoStore: any MealPhotoStoring,
        healthDataRevision: Int = 0
    ) {
        self.photoStore = photoStore
        self.healthDataRevision = healthDataRevision
        _viewModel = State(
            initialValue: MealHistoryViewModel(repository: repository)
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: "饮食历史") {
            HistoryDateSelector(selectedDate: $viewModel.selectedDate)

            Picker("筛选餐次", selection: $viewModel.selectedMeal) {
                Text("全部").tag(nil as MealPeriod?)
                ForEach(viewModel.mealOptions) { option in
                    Text(option.rawValue).tag(option as MealPeriod?)
                }
            }
            .pickerStyle(.segmented)

            SectionHeader("餐食记录", subtitle: viewModel.recordSubtitle)

            if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "暂时无法读取历史记录",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if viewModel.meals.isEmpty {
                ContentUnavailableView(
                    "当天没有匹配的餐食记录",
                    systemImage: "fork.knife.circle",
                    description: Text("可以切换日期或餐次继续查询。")
                )
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.meals) { meal in
                        NavigationLink {
                            MealReviewDetailView(
                                meal: meal,
                                photoStore: photoStore
                            )
                        } label: {
                            MealRecordCard(meal: meal)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meal-history-record-\(meal.id.uuidString)")
                    }
                }
            }
        }
        .refreshable(action: viewModel.load)
        .task(
            id: "\(viewModel.selectedDate.timeIntervalSinceReferenceDate)-\(viewModel.selectedMeal?.rawValue ?? "全部")-\(healthDataRevision)"
        ) {
            viewModel.load()
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        MealHistoryView(
            repository: dependencies.mealRepository,
            photoStore: dependencies.mealPhotoStore
        )
    }
    .modelContainer(dependencies.modelContainer)
}
