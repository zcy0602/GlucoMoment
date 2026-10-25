//
//  MealLogDemoView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftData
import SwiftUI

struct MealLogDemoView: View {
    private let analysisService: any FoodAnalysisService
    private let photoStore: any MealPhotoStoring
    private let repository: any MealRepository
    private let healthDataRevision: Int
    @State private var viewModel: MealLogViewModel

    init(
        repository: any MealRepository,
        analysisService: any FoodAnalysisService,
        photoStore: any MealPhotoStoring,
        healthDataRevision: Int = 0
    ) {
        self.repository = repository
        self.analysisService = analysisService
        self.photoStore = photoStore
        self.healthDataRevision = healthDataRevision
        _viewModel = State(initialValue: MealLogViewModel(repository: repository))
    }

    var body: some View {
        DemoScreen(title: viewModel.title) {
            MealSuggestionCard(
                title: viewModel.suggestionTitle,
                text: viewModel.suggestionText,
                tags: viewModel.suggestionTags
            )

            NavigationLink {
                FoodScanDemoView(
                    analysisService: analysisService,
                    mealRepository: repository,
                    photoStore: photoStore
                )
            } label: {
                Label("拍照识别饮食", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.brandMint)
            .controlSize(.large)

            SectionHeader("今日餐食")
            if let loadErrorMessage = viewModel.loadErrorMessage {
                ContentUnavailableView(
                    "暂时无法读取饮食记录",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadErrorMessage)
                )
            } else if viewModel.meals.isEmpty {
                ContentUnavailableView(
                    "今天还没有餐食记录",
                    systemImage: "fork.knife.circle",
                    description: Text("拍摄餐食并确认识别结果后，会保存在这里。")
                )
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 20) {
                    ForEach(viewModel.mealSections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                section.period.rawValue,
                                subtitle: "\(section.meals.count) 条记录"
                            )

                            ForEach(section.meals) { meal in
                                NavigationLink {
                                    MealReviewDetailView(
                                        meal: meal,
                                        photoStore: photoStore
                                    )
                                } label: {
                                    MealRecordCard(meal: meal)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("meal-record-\(meal.id.uuidString)")
                                .contextMenu {
                                    if meal.source != .healthKit {
                                        Button("删除记录", systemImage: "trash", role: .destructive) {
                                            Task { await viewModel.delete(meal) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: healthDataRevision) {
            viewModel.reload()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    MealHistoryView(
                        repository: repository,
                        photoStore: photoStore,
                        healthDataRevision: healthDataRevision
                    )
                } label: {
                    Label("历史记录", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("meal-history-link")
            }
        }
    }
}

private struct MealSuggestionCard: View {
    let title: String
    let text: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                PillTag(title: "可执行", tint: Color.brandTeal)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    PillTag(title: tag, tint: Color.brandLeaf)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct MealRecordCard: View {
    let meal: MealRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(meal.title)
                        .font(.headline)
                    Text(
                        "\(meal.eatenAt.formatted(GlucoMomentDateStyle.time)) · \(carbohydrateSummary)"
                    )
                        .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    CaloriesBadge(
                        calories: meal.nutritionAvailability.contains(.energy)
                            ? meal.caloriesKcal : nil
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if let note = meal.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(meal.items.prefix(4)) { item in
                    PillTag(title: item.name, tint: Color.brandTeal)
                }
                PillTag(
                    title: meal.source.label,
                    tint: Color.brandLeaf
                )

            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }

    private var carbohydrateSummary: String {
        guard meal.nutritionAvailability.contains(.carbohydrates) else {
            return "碳水未提供"
        }
        return "\(meal.carbohydratesGrams.formatted(.number.precision(.fractionLength(0))))g 碳水"
    }
}

private struct CaloriesBadge: View {
    let calories: Double?

    var body: some View {
        VStack(spacing: 2) {
            Text(calories?.formatted(.number.precision(.fractionLength(0))) ?? "—")
                .font(.title3.weight(.bold))
            Text("千卡")
                .font(.caption2)
        }
        .foregroundStyle(Color.brandLeaf)
        .frame(width: 62, height: 54)
        .background(Color.brandLeaf.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        MealLogDemoView(
            repository: dependencies.mealRepository,
            analysisService: dependencies.foodAnalysisService,
            photoStore: dependencies.mealPhotoStore
        )
    }
    .modelContainer(dependencies.modelContainer)
}
