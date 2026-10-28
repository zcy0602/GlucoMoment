//
//  MealResultView.swift
//  GlucoMoment
//

import SwiftUI

/// 识别结果页：结果直接可改，不再单独打开「检查并修改」。
/// 点食物进编辑表单；底部输入框用一句话修正；稳糖分随修改实时重算
struct MealResultContent: View {
    @Bindable var viewModel: FoodScanViewModel

    @State private var correctionText = ""
    @State private var correctionTask: Task<Void, Never>?
    @State private var correctionError: String?
    /// 每次修正前的结果，用于撤销上一次修正
    @State private var resultsBeforeCorrection: [FoodRecognitionResult] = []
    @State private var correctedItemIDs: Set<UUID> = []
    @State private var editingItem: EditingFoodItem?
    @State private var isShowingBreakdown = false
    /// 正在回答 AI 的哪个问题；发送时会带上问题，帮模型理解
    @State private var answeringQuestion: String?
    /// 取自照片的用餐时间；用户改了时间后不再提示
    @State private var photoCaptureDate: Date?
    @FocusState private var isCorrectionFocused: Bool

    private var isCorrecting: Bool { correctionTask != nil }

    var body: some View {
        if let result = viewModel.result {
            ScrollView {
                VStack(spacing: 16) {
                    MealPhotoHeader(photos: viewModel.selectedPhotos)
                    titleSection

                    StableScoreSummaryCard(
                        score: result.effectiveScore,
                        breakdown: result.stableScore,
                        fallbackImpact: result.glucoseImpact
                    ) {
                        isShowingBreakdown = true
                    }

                    NutritionStrip(
                        caloriesKcal: result.caloriesKcal,
                        carbohydratesGrams: result.carbohydratesGrams,
                        proteinGrams: result.proteinGrams,
                        fatGrams: result.fatGrams
                    )
                    .cardBackground(padding: 14)

                    foodsCard(result)

                    if !viewModel.correctionHistory.isEmpty {
                        correctionLogCard
                    }

                    if !result.followUpQuestions.isEmpty || !result.uncertainties.isEmpty {
                        questionsCard(result)
                    }

                    if !result.effectiveSuggestions.isEmpty {
                        MealSuggestionsCard(
                            suggestions: result.effectiveSuggestions,
                            citation: result.suggestionCitation
                        )
                    }

                    if case .failed(let message) = viewModel.phase {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.brandRose)
                            .cardBackground()
                    }

                    MealDisclaimerFooter()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                correctionBar
            }
            .sheet(item: $editingItem) { editing in
                FoodItemEditorView(item: itemBinding(editing.id)) {
                    withAnimation(.snappy) {
                        viewModel.result?.items.removeAll { $0.id == editing.id }
                    }
                }
            }
            .sheet(isPresented: $isShowingBreakdown) {
                ScoreBreakdownView(score: result.effectiveScore, breakdown: result.stableScore)
            }
            .onAppear {
                if photoCaptureDate == nil, viewModel.isEatenAtFromPhoto {
                    photoCaptureDate = viewModel.eatenAt
                }
            }
            .onDisappear {
                correctionTask?.cancel()
            }
        }
    }

    // MARK: 名称与时间

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("给这一餐起个名字", text: nameBinding, axis: .vertical)
                .font(.title2.weight(.bold))
                .lineLimit(1...2)

            HStack(spacing: 8) {
                Picker("餐次", selection: $viewModel.selectedMealPeriod) {
                    ForEach(MealPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                DatePicker("用餐时间", selection: $viewModel.eatenAt, in: ...Date.now)
                    .labelsHidden()
                    .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
            }

            if let photoCaptureDate, photoCaptureDate == viewModel.eatenAt {
                Label("时间取自照片的拍摄时间", systemImage: "camera")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var nameBinding: Binding<String> {
        Binding {
            viewModel.result?.name ?? ""
        } set: { name in
            viewModel.result?.name = name
        }
    }

    // MARK: 食物

    private func foodsCard(_ result: FoodRecognitionResult) -> some View {
        SummaryCard(
            title: "食物",
            systemImage: "fork.knife",
            tint: .mealTint,
            detail: "\(result.items.count) 样 · 点按修改"
        ) {
            VStack(spacing: 0) {
                ForEach(result.items) { item in
                    Button {
                        editingItem = EditingFoodItem(id: item.id)
                    } label: {
                        HStack(spacing: 8) {
                            FoodItemRow(
                                name: item.name,
                                category: item.foodCategory,
                                portionDescription: item.portionDescription,
                                estimatedGrams: item.estimatedGrams,
                                carbohydratesGrams: item.carbohydratesGrams,
                                isHighlighted: correctedItemIDs.contains(item.id)
                            )
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isCorrecting)

                    if item.id != result.items.last?.id {
                        Divider()
                            .padding(.leading, 22)
                            .padding(.vertical, 4)
                    }
                }

                Button {
                    addItem()
                } label: {
                    Label("添加食物", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .tint(Color.mealTint)
                .padding(.top, 12)
                .disabled(isCorrecting)
            }
        }
    }

    private func itemBinding(_ id: UUID) -> Binding<FoodRecognitionItem> {
        Binding {
            viewModel.result?.items.first { $0.id == id } ?? FoodRecognitionItem.blank
        } set: { updated in
            guard let index = viewModel.result?.items.firstIndex(where: { $0.id == id }) else { return }
            viewModel.result?.items[index] = updated
        }
    }

    private func addItem() {
        let item = FoodRecognitionItem.blank
        withAnimation(.snappy) {
            viewModel.result?.items.append(item)
        }
        editingItem = EditingFoodItem(id: item.id)
    }

    // MARK: AI 的追问

    private func questionsCard(_ result: FoodRecognitionResult) -> some View {
        SummaryCard(title: "AI 想和你确认", systemImage: "questionmark.bubble", tint: .brandAmber) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(result.followUpQuestions, id: \.self) { question in
                    Button {
                        answeringQuestion = question
                        isCorrectionFocused = true
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text("回答")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.insightTint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(result.uncertainties, id: \.self) { uncertainty in
                    Text(uncertainty)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 一句话修正

    private var correctionLogCard: some View {
        SummaryCard(title: "修正记录", systemImage: "text.bubble", tint: .insightTint) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(viewModel.correctionHistory.enumerated()), id: \.offset) { _, turn in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(turn.instruction)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.insightTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Label(turn.reply, systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !resultsBeforeCorrection.isEmpty, !isCorrecting {
                    Button("撤销上一次修正", systemImage: "arrow.uturn.backward", action: undoLastCorrection)
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.borderless)
                        .tint(Color.insightTint)
                }
            }
        }
    }

    private var trimmedCorrection: String {
        correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var correctionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let correctionError {
                Label(correctionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.brandRose)
                    .padding(.horizontal, 20)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if let answeringQuestion {
                    Button("取消回答", systemImage: "xmark.circle.fill") {
                        self.answeringQuestion = nil
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .accessibilityHint("正在回答：\(answeringQuestion)")
                }

                TextField(placeholder, text: $correctionText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isCorrectionFocused)
                    .disabled(isCorrecting)
                    .padding(.vertical, 8)

                if isCorrecting {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Button("发送修正", systemImage: "arrow.up.circle.fill", action: sendCorrection)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 30))
                        .tint(Color.insightTint)
                        .disabled(trimmedCorrection.isEmpty)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var placeholder: String {
        if let answeringQuestion {
            return "回答：\(answeringQuestion)"
        }
        return viewModel.correctionHistory.isEmpty ? "哪里不对？说一句，比如“米饭只吃了半碗”" : "还有哪里不对？"
    }

    private func sendCorrection() {
        let text = trimmedCorrection
        guard !text.isEmpty, correctionTask == nil, let snapshot = viewModel.result else { return }

        let instruction = String(
            (answeringQuestion.map { "关于“\($0)”：\(text)" } ?? text)
                .prefix(FoodCorrectionLimit.maxInstructionLength)
        )
        correctionError = nil
        isCorrectionFocused = false
        let history = viewModel.correctionHistory
        let period = viewModel.selectedMealPeriod

        correctionTask = Task {
            defer { correctionTask = nil }
            do {
                let outcome = try await viewModel.correct(
                    snapshot,
                    instruction: instruction,
                    history: history,
                    mealPeriod: period
                )
                try Task.checkCancellation()
                withAnimation(.snappy) {
                    resultsBeforeCorrection.append(snapshot)
                    viewModel.result = outcome.result
                    correctedItemIDs = outcome.changedItemIDs
                    viewModel.correctionHistory.append(
                        FoodCorrectionTurn(instruction: instruction, reply: outcome.reply)
                    )
                }
                correctionText = ""
                answeringQuestion = nil
            } catch is CancellationError {
                return
            } catch {
                correctionError = error.localizedDescription
            }
        }
    }

    /// 回到上一次修正之前；之后手动做的修改也会一并撤销
    private func undoLastCorrection() {
        guard let previous = resultsBeforeCorrection.popLast() else { return }
        withAnimation(.snappy) {
            viewModel.result = previous
            correctedItemIDs = []
            if !viewModel.correctionHistory.isEmpty {
                viewModel.correctionHistory.removeLast()
            }
        }
    }
}

/// 正在编辑的食物，作为 sheet 的 item
private struct EditingFoodItem: Identifiable {
    let id: UUID
}

extension FoodRecognitionItem {
    /// 手动添加的空白食物
    static var blank: FoodRecognitionItem {
        FoodRecognitionItem(
            name: "",
            portionDescription: "",
            estimatedGrams: 0,
            caloriesKcal: 0,
            carbohydratesGrams: 0,
            proteinGrams: 0,
            fatGrams: 0,
            fiberGrams: 0,
            confidence: 1,
            evidence: "用户手动添加",
            foodCategory: .other
        )
    }
}

// MARK: - 食物编辑

/// 单样食物的编辑表单。改动直接写回识别结果，稳糖分随之重算
struct FoodItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var item: FoodRecognitionItem
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $item.name)
                    TextField("份量，例如：半碗", text: $item.portionDescription)
                    Picker("类别", selection: $item.foodCategory) {
                        Text("未选择").tag(FoodCategory?.none)
                        ForEach(FoodCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(Optional(category))
                        }
                    }
                } footer: {
                    Text("类别决定这样食物的升糖指数，是计算稳糖分的依据。")
                }

                Section("份量") {
                    numberRow("重量", value: $item.estimatedGrams, unit: "克")
                    numberRow("热量", value: $item.caloriesKcal, unit: "千卡")
                }

                Section {
                    numberRow("碳水", value: $item.carbohydratesGrams, unit: "克")
                    numberRow("膳食纤维", value: $item.fiberGrams, unit: "克")
                    numberRow("蛋白质", value: $item.proteinGrams, unit: "克")
                    numberRow("脂肪", value: $item.fatGrams, unit: "克")
                } header: {
                    Text("营养")
                } footer: {
                    Text("碳水填总量，计算时会自动扣除膳食纤维。")
                }

                if !item.evidence.isEmpty {
                    Section("识别依据") {
                        Text(item.evidence)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("删除这样食物", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle(item.name.isEmpty ? "添加食物" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
