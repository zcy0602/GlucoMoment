//
//  MealsDiaryView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 新版饮食页：日期条 + 当天汇总 + 按餐次分组的记录。右上角相机记录新的一餐。
/// 合并了旧版的「饮食记录」和「历史记录」两个页面
struct MealsDiaryView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: MealsDiaryViewModel
    @State private var captureSource: MealPhotoSource?

    init(dependencies: AppDependencies, healthDataRevision: Int) {
        _viewModel = State(initialValue: MealsDiaryViewModel(repository: dependencies.mealRepository))
        self.dependencies = dependencies
        self.healthDataRevision = healthDataRevision
    }

    var body: some View {
        List {
            Section {
                DayStrip(
                    days: viewModel.days,
                    selectedDate: viewModel.selectedDate,
                    today: viewModel.today,
                    hasMeals: viewModel.hasMeals(on:)
                ) { day in
                    withAnimation(.snappy) { viewModel.select(day) }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.meals.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    daySummary
                }

                ForEach(viewModel.sections) { section in
                    Section(section.period.rawValue) {
                        ForEach(section.meals) { meal in
                            NavigationLink {
                                MealDetailView(meal: meal, dependencies: dependencies) {
                                    viewModel.load()
                                }
                            } label: {
                                MealListRow(meal: meal, photoStore: dependencies.mealPhotoStore)
                            }
                            .swipeActions {
                                if meal.source != .healthKit {
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        Task { await viewModel.delete(meal) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("饮食")
        .navigationSubtitle(viewModel.selectedDate.formatted(Self.subtitleStyle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("拍照", systemImage: "camera") { captureSource = .camera }
                    Button("从相册选择", systemImage: "photo.on.rectangle") { captureSource = .library }
                } label: {
                    Label("记录一餐", systemImage: "camera.fill")
                }
            }
        }
        .mealCapture(source: $captureSource, dependencies: dependencies) {
            viewModel.load()
            viewModel.select(viewModel.today)
        }
        .refreshable {
            await dependencies.healthKitCoordinator.refresh()
            viewModel.load()
        }
        .task(id: healthDataRevision) { viewModel.load() }
    }

    static let subtitleStyle = Date.FormatStyle()
        .month(.abbreviated)
        .day()
        .weekday(.wide)
        .locale(GlucoMomentDateStyle.mainlandChinaLocale)

    private var daySummary: some View {
        HStack(spacing: 0) {
            summaryValue(DisplayFormat.whole(viewModel.totalCalories), unit: "千卡", title: "热量")
            Divider().frame(height: 36)
            summaryValue(DisplayFormat.whole(viewModel.totalCarbohydrates), unit: "克", title: "碳水", tint: .mealTint)
            Divider().frame(height: 36)
            VStack(spacing: 4) {
                ScoreRing(score: viewModel.averageScore, diameter: 40)
                Text("平均稳糖分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
    }

    private func summaryValue(_ value: String, unit: String, title: String, tint: Color = .primary) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(viewModel.isSelectedToday ? "今天还没有记录" : "这天没有记录", systemImage: "fork.knife")
        } description: {
            if viewModel.isSelectedToday {
                Text("拍下这一餐，AI 会估算营养和稳糖分。")
            }
        } actions: {
            if viewModel.isSelectedToday {
                Button {
                    captureSource = .camera
                } label: {
                    Label("拍照记录", systemImage: "camera.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button("从相册选择") {
                    captureSource = .library
                }
            }
        }
    }
}

/// 饮食列表的一行：缩略图、名称、时间与热量，右侧稳糖分
struct MealListRow: View {
    let meal: MealRecord
    let photoStore: any MealPhotoStoring

    var body: some View {
        HStack(spacing: 12) {
            MealPhotoThumbnail(filename: meal.photoFilename, photoStore: photoStore, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let score = meal.score {
                ScoreRing(score: score, diameter: 38)
            } else if meal.source == .healthKit {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .accessibilityLabel("来自健康 App")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let time = meal.eatenAt.formatted(GlucoMomentDateStyle.time)
        return "\(time) · \(DisplayFormat.whole(meal.caloriesKcal)) 千卡 · 碳水 \(DisplayFormat.whole(meal.carbohydratesGrams)) 克"
    }
}

/// 横向滚动的日期条，最右边是今天；有记录的日期下方有小圆点
struct DayStrip: View {
    let days: [Date]
    let selectedDate: Date
    let today: Date
    let hasMeals: (Date) -> Bool
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .defaultScrollAnchor(.trailing)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(day, inSameDayAs: today)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 6) {
                Text(isToday ? "今" : day.formatted(GlucoMomentDateStyle.weekday))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isToday ? Color.brandTeal : .secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.brandTeal : .primary))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isSelected ? Color.brandTeal : .clear))
                Circle()
                    .fill(hasMeals(day) ? Color.mealTint : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(MealsDiaryView.subtitleStyle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        MealsDiaryView(dependencies: dependencies, healthDataRevision: 0)
    }
    .modelContainer(dependencies.modelContainer)
}
