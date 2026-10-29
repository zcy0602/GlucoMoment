//
//  MealsDiaryView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 新版饮食页：日期条 + 当天汇总 + 下一餐提示 + 按时间排列的记录。右上角相机记录新的一餐。
/// 合并了旧版的「饮食记录」和「历史记录」两个页面
struct MealsDiaryView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var viewModel: MealsDiaryViewModel
    /// 只用于「下一餐提示」：按今天已记录的餐套用规则，没有触发时显示当前餐次的通用建议
    @State private var tipViewModel: MealLogViewModel
    @State private var captureSource: MealPhotoSource?

    init(dependencies: AppDependencies, healthDataRevision: Int) {
        _viewModel = State(initialValue: MealsDiaryViewModel(repository: dependencies.mealRepository))
        _tipViewModel = State(initialValue: MealLogViewModel(repository: dependencies.mealRepository))
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
                tipSection
            } else {
                Section {
                    daySummary
                }

                tipSection

                Section {
                    ForEach(viewModel.meals) { meal in
                        NavigationLink {
                            MealDetailView(meal: meal, dependencies: dependencies) {
                                reload()
                            }
                        } label: {
                            MealListRow(meal: meal, photoStore: dependencies.mealPhotoStore)
                        }
                        .swipeActions {
                            if meal.source != .healthKit {
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    Task {
                                        await viewModel.delete(meal)
                                        tipViewModel.reload()
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("拍照", systemImage: "camera") { captureSource = .camera }
                    Button("从相册选择", systemImage: "photo.on.rectangle") { captureSource = .library }
                } label: {
                    Label("记录一餐", systemImage: "camera.fill")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(dependencies: dependencies)
            }
        }
        .mealCapture(source: $captureSource, dependencies: dependencies) {
            reload()
            viewModel.select(viewModel.today)
        }
        .refreshable {
            await dependencies.healthKitCoordinator.refresh()
            reload()
        }
        .task(id: healthDataRevision) { reload() }
    }

    private func reload() {
        viewModel.load()
        tipViewModel.reload()
    }

    /// 只在选中今天时显示；回看以前的日期时提示没有意义
    @ViewBuilder
    private var tipSection: some View {
        if viewModel.isSelectedToday {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tipViewModel.suggestionTitle, systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brandAmber)
                    Text(tipViewModel.suggestionText)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tipViewModel.suggestionCitation)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    static let subtitleStyle = Date.FormatStyle()
        .month(.abbreviated)
        .day()
        .weekday(.wide)
        .locale(GlucoMomentDateStyle.mainlandChinaLocale)

    /// 三栏的数值区等高（与圆环同高）并垂直居中，下方标签因此落在同一条线上
    private static let summaryValueHeight: CGFloat = 44

    private var daySummary: some View {
        HStack(spacing: 0) {
            summaryColumn(title: "热量") {
                summaryNumber(DisplayFormat.whole(viewModel.totalCalories), unit: "千卡")
            }
            Divider().frame(height: 40)
            summaryColumn(title: "碳水") {
                summaryNumber(DisplayFormat.whole(viewModel.totalCarbohydrates), unit: "克", tint: .mealTint)
            }
            Divider().frame(height: 40)
            summaryColumn(title: "平均稳糖分") {
                ScoreRing(score: viewModel.averageScore, diameter: Self.summaryValueHeight)
            }
        }
        .padding(.vertical, 8)
    }

    private func summaryColumn<Value: View>(title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 6) {
            value()
                .frame(height: Self.summaryValueHeight)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryNumber(_ value: String, unit: String, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 4)
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
                // 标题不限行数，长名称自动换行显示完整
                Text(meal.title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    capsule(meal.mealPeriod.rawValue, tint: .mealTint)
                    Text(meal.eatenAt, format: GlucoMomentDateStyle.time)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // 营养用灰色胶囊，和带颜色的餐次区分主次
                HStack(spacing: 6) {
                    capsule("\(DisplayFormat.whole(meal.caloriesKcal)) 千卡", tint: .secondary)
                    capsule("碳水 \(DisplayFormat.whole(meal.carbohydratesGrams)) 克", tint: .secondary)
                }
            }

            Spacer(minLength: 8)

            if let score = meal.score {
                VStack(spacing: 6) {
                    ScoreRing(score: score, diameter: 38)
                    Text("稳糖分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if meal.source == .healthKit {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .accessibilityLabel("来自健康 App")
            }
        }
        .padding(.vertical, 2)
    }

    private func capsule(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
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
