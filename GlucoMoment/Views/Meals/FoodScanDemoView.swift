//
//  FoodScanDemoView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/7/6.
//

import PhotosUI
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

struct FoodScanDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FoodScanViewModel
    /// 新的一餐：替换全部照片
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    /// 在补充信息页为同一餐追加照片
    @State private var appendedPhotoItems: [PhotosPickerItem] = []
    @State private var presentedSheet: FoodScanSheet?
    @State private var photoSelectionIssue: PhotoSelectionIssue?
    @State private var isLoadingPhoto = false

    init(
        analysisService: any FoodAnalysisService,
        mealRepository: any MealRepository,
        photoStore: any MealPhotoStoring
    ) {
        _viewModel = State(
            initialValue: FoodScanViewModel(
                analysisService: analysisService,
                mealRepository: mealRepository,
                photoStore: photoStore
            )
        )
    }

#if DEBUG
    fileprivate init(previewViewModel: FoodScanViewModel) {
        _viewModel = State(initialValue: previewViewModel)
    }
#endif

    var body: some View {
        DemoScreen(title: viewModel.title) {
            if !viewModel.selectedPhotos.isEmpty {
                CameraPreviewCard(
                    photos: viewModel.selectedPhotos,
                    title: viewModel.result?.name ?? "待识别餐食",
                    stateText: viewModel.scanStateText
                )
                PhotoActionRow(
                    selectedPhotoItems: $selectedPhotoItems,
                    maxSelectionCount: viewModel.maxPhotoCount,
                    onCameraTap: { openCamera(appending: false) }
                )

                scanContent
            } else {
                PhotoSourceCard(
                    selectedPhotoItems: $selectedPhotoItems,
                    maxSelectionCount: viewModel.maxPhotoCount,
                    isLoading: isLoadingPhoto,
                    onCameraTap: { openCamera(appending: false) }
                )
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .camera, .cameraAppend:
#if os(iOS)
                let appending = destination == .cameraAppend
                CameraPicker(
                    onImageSelected: { image in
                        guard let data = image.jpegData(compressionQuality: 0.9) else {
                            photoSelectionIssue = PhotoSelectionIssue(message: "拍摄的照片无法读取，请重试。")
                            return
                        }

                        if appending {
                            viewModel.addPhotos([data])
                            presentedSheet = .context
                        } else {
                            applySelectedPhotos([data])
                        }
                    },
                    onCancel: appending ? { presentedSheet = .context } : nil
                )
#else
                EmptyView()
#endif
            case .context:
                FoodContextSheet(
                    viewModel: viewModel,
                    appendedPhotoItems: $appendedPhotoItems,
                    isLoadingPhoto: isLoadingPhoto,
                    onTakePhoto: { openCamera(appending: true) }
                )
            case .review:
                FoodReviewSheet(viewModel: viewModel)
            }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }

            Task {
                if let photos = await loadPhotos(from: items) {
                    applySelectedPhotos(photos)
                }
                selectedPhotoItems = []
            }
        }
        .onChange(of: appendedPhotoItems) { _, items in
            guard !items.isEmpty else { return }

            Task {
                if let photos = await loadPhotos(from: items) {
                    withAnimation(.snappy) {
                        viewModel.addPhotos(photos)
                    }
                }
                appendedPhotoItems = []
            }
        }
        .alert(item: $photoSelectionIssue) { issue in
            Alert(
                title: Text("无法使用照片"),
                message: Text(issue.message),
                dismissButton: .default(Text("好"))
            )
        }
        .onDisappear {
            viewModel.cancelAnalysis()
        }
    }

    @ViewBuilder
    private var scanContent: some View {
        if let result = viewModel.result {
            if !viewModel.userFoodContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserFoodContextCard(text: viewModel.userFoodContext)
            }

            RecognitionSummaryCard(result: result)
            NutritionGrid(result: result)
            StableScoreCard(result: result)
            SuggestionListCard(suggestions: result.suggestions)

            if !result.uncertainties.isEmpty || !result.followUpQuestions.isEmpty {
                UncertaintyListCard(
                    uncertainties: result.uncertainties,
                    questions: result.followUpQuestions
                )
            }

            if case .failed(let message) = viewModel.phase {
                InlineIssueCard(message: message)
            }

            Button {
                presentedSheet = .review
            } label: {
                Label("检查并修改识别结果", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.isBusy || viewModel.phase == .saved)

            Button {
                Task {
                    await viewModel.save()
                }
            } label: {
                if viewModel.phase == .saving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(
                        viewModel.saveButtonTitle,
                        systemImage: viewModel.phase == .saved
                            ? "checkmark.circle.fill"
                            : "tray.and.arrow.down.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isBusy || viewModel.phase == .saved)
        } else {
            switch viewModel.phase {
            case .awaitingContext:
                ContextPromptCard {
                    presentedSheet = .context
                }
            case .preparingImage:
                AnalysisProgressCard(
                    title: "正在优化照片",
                    detail: "压缩图片并移除位置等元数据…"
                )
            case .analyzing:
                AnalysisProgressCard(
                    title: "正在识别餐食",
                    detail: "正在结合照片和你的描述估算食物与营养信息…"
                )
            case .failed(let message):
                InlineIssueCard(message: message)
                Button {
                    presentedSheet = .context
                } label: {
                    Label("修改描述并重试", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .idle, .needsReview, .saving, .saved:
                EmptyView()
            }
        }
    }

    private func openCamera(appending: Bool) {
#if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            photoSelectionIssue = PhotoSelectionIssue(
                message: "当前设备没有可用的相机，可以改从图库选择照片。"
            )
            return
        }

        presentedSheet = appending ? .cameraAppend : .camera
#else
        photoSelectionIssue = PhotoSelectionIssue(message: "当前平台不支持在 App 内拍照。")
#endif
    }

    /// 按选择顺序读取照片；任一张失败时整体放弃，避免一餐只录入部分照片
    private func loadPhotos(from items: [PhotosPickerItem]) async -> [Data]? {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        do {
            var photos: [Data] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self),
                      !data.isEmpty else {
                    throw PhotoLoadingError.invalidData
                }
                photos.append(data)
            }
            return photos
        } catch {
            photoSelectionIssue = PhotoSelectionIssue(
                message: "图库中的照片加载失败，请换一张照片或重试。"
            )
            return nil
        }
    }

    private func applySelectedPhotos(_ photos: [Data]) {
        withAnimation(.snappy) {
            viewModel.selectPhotos(photos)
        }
        presentedSheet = .context
    }
}

private enum FoodScanSheet: String, Identifiable {
    case camera
    case cameraAppend
    case context
    case review

    var id: String { rawValue }
}

private struct PhotoSelectionIssue: Identifiable {
    let id = UUID()
    let message: String
}

private enum PhotoLoadingError: Error {
    case invalidData
}

private struct FoodContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: FoodScanViewModel
    @Binding var appendedPhotoItems: [PhotosPickerItem]
    let isLoadingPhoto: Bool
    let onTakePhoto: () -> Void

    private let hintColumns = [
        GridItem(
            .adaptive(minimum: 132),
            spacing: 8,
            alignment: .leading
        )
    ]

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    ContextPhotoStrip(
                        photos: viewModel.selectedPhotos,
                        onRemove: { index in
                            withAnimation(.snappy) {
                                viewModel.removePhoto(at: index)
                            }
                        }
                    )

                    if isLoadingPhoto {
                        ProgressView("正在读取照片…")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.remainingPhotoSlots > 0 {
                        HStack(spacing: 12) {
#if os(iOS)
                            Button(action: onTakePhoto) {
                                Label("拍一张", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
#endif
                            PhotosPicker(
                                selection: $appendedPhotoItems,
                                maxSelectionCount: viewModel.remainingPhotoSlots,
                                selectionBehavior: .ordered,
                                matching: .images
                            ) {
                                Label("从图库添加", systemImage: "photo.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } header: {
                    Text("照片 \(viewModel.selectedPhotos.count)/\(viewModel.maxPhotoCount)")
                } footer: {
                    Text("同一餐的其他菜或另一个角度可以继续添加，会一起识别。")
                }

                Section {
                    Text("可以补充照片里不容易看出的份量、烹饪方式、酱汁或配料。留空也可以继续识别。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $viewModel.userFoodContext)
                        .frame(minHeight: 120)
                        .onChange(of: viewModel.userFoodContext) { _, newValue in
                            if newValue.count > 500 {
                                viewModel.userFoodContext = String(newValue.prefix(500))
                            }
                        }
                        .accessibilityLabel("食物补充描述")

                    HStack {
                        Text("例如：半碗米饭，鸡肉清炒，加了一勺酱油。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.userFoodContext.count)/500")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("描述一下这份食物")
                }

                Section("可以补充") {
                    LazyVGrid(
                        columns: hintColumns,
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(["份量", "烹饪方式", "酱汁与用油", "包装营养信息", "实际吃掉的比例"], id: \.self) { hint in
                            Button(hint) {
                                appendHint(hint)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("补充食物信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Menu("完成") {
                        Section(
                            viewModel.selectedPhotos.count > 1
                                ? "确认用 \(viewModel.selectedPhotos.count) 张照片识别？"
                                : "确认开始识别？"
                        ) {
                            Button("开始识别", systemImage: "sparkles") {
                                startAnalysis(skipDescription: false)
                            }

                            // 只有填写了补充信息时，“忽略”才有意义
                            if !viewModel.userFoodContext
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty {
                                Button("忽略补充信息并识别", systemImage: "text.badge.minus") {
                                    startAnalysis(skipDescription: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func appendHint(_ hint: String) {
        let separator = viewModel.userFoodContext.isEmpty ? "" : "\n"
        let proposed = viewModel.userFoodContext + separator + "\(hint)："
        viewModel.userFoodContext = String(proposed.prefix(500))
    }

    private func startAnalysis(skipDescription: Bool) {
        dismiss()
        viewModel.startAnalysis(skipDescription: skipDescription)
    }
}

private struct FoodReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: FoodScanViewModel

    @State private var draft: FoodRecognitionResult
    @State private var selectedMealPeriod: MealPeriod
    @State private var eatenAt: Date
    @State private var userNote: String
    @State private var correctionHistory: [FoodCorrectionTurn]
    /// 每次修正前的草稿，与本次打开后新增的修正一一对应，用于撤销上一次修正
    @State private var draftsBeforeCorrection: [FoodRecognitionResult] = []
    @State private var correctedItemIDs: Set<UUID> = []
    @State private var correctionText = ""
    @State private var correctionTask: Task<Void, Never>?
    @State private var correctionError: String?
    @FocusState private var isCorrectionFocused: Bool

    init(viewModel: FoodScanViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.result ?? .empty)
        _selectedMealPeriod = State(initialValue: viewModel.selectedMealPeriod)
        _eatenAt = State(initialValue: viewModel.eatenAt)
        _userNote = State(initialValue: viewModel.userNote)
        _correctionHistory = State(initialValue: viewModel.correctionHistory)
    }

    private var isCorrecting: Bool {
        correctionTask != nil
    }

    private var trimmedCorrection: String {
        correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("稳糖分") {
                        Text("\(draft.effectiveScore)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.brandLeaf)
                            .contentTransition(.numericText())
                    }
                    if let breakdown = draft.stableScore {
                        Text(breakdown.summaryText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(
                        draft.stableScore == nil
                            ? "有食物没有选择类别，暂时显示 AI 估算的分数。为每样食物选择类别后，将按公式计算。"
                            : "修改食物的类别、重量或营养数值后，稳糖分会实时重新计算。"
                    )
                }

                Section {
                    ForEach(Array(correctionHistory.enumerated()), id: \.offset) { _, turn in
                        CorrectionTurnRow(turn: turn)
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("比如：米饭只吃了半碗，还有一个卤蛋", text: $correctionText, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($isCorrectionFocused)
                            .disabled(isCorrecting)

                        if isCorrecting {
                            ProgressView()
                                .frame(width: 28, height: 28)
                        } else {
                            Button("发送修正", systemImage: "arrow.up.circle.fill", action: sendCorrection)
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .tint(Color.brandTeal)
                                .buttonStyle(.borderless)
                                .disabled(trimmedCorrection.isEmpty)
                        }
                    }

                    if let correctionError {
                        Label(correctionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.brandRose)
                    }

                    if !draftsBeforeCorrection.isEmpty, !isCorrecting {
                        Button("撤销上一次修正", systemImage: "arrow.uturn.backward", action: undoLastCorrection)
                            .font(.subheadline)
                    }
                } header: {
                    Text("一句话修正")
                } footer: {
                    Text("说说哪里不对，AI 只改你提到的食物，稳糖分仍按公式计算。可以接着说，连续修正。")
                }

                Section("餐食信息") {
                    TextField("餐食名称", text: $draft.name)
                    Picker("餐次", selection: $selectedMealPeriod) {
                        ForEach(MealPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    DatePicker("用餐时间", selection: $eatenAt)
                        .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                    TextField("备注（可选）", text: $userNote, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach($draft.items) { $item in
                        FoodItemEditor(
                            item: $item,
                            isRecentlyCorrected: correctedItemIDs.contains(item.id)
                        ) {
                            draft.items.removeAll { $0.id == item.id }
                        }
                        .listRowBackground(
                            correctedItemIDs.contains(item.id) ? Color.brandTeal.opacity(0.1) : nil
                        )
                    }

                    Button("添加食物", systemImage: "plus") {
                        draft.items.append(
                            FoodRecognitionItem(
                                name: "新食物",
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
                        )
                    }
                } header: {
                    Text("食物与营养")
                } footer: {
                    Text("照片识别只能提供估算，请根据实际份量进行调整。")
                }
                // 修正返回前锁定手动编辑，避免返回的结果覆盖刚改的内容
                .disabled(isCorrecting)
            }
            .navigationTitle("检查识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        viewModel.result = draft
                        viewModel.selectedMealPeriod = selectedMealPeriod
                        viewModel.eatenAt = eatenAt
                        viewModel.userNote = userNote
                        viewModel.correctionHistory = correctionHistory
                        dismiss()
                    }
                    .disabled(
                        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.items.isEmpty
                            || isCorrecting
                    )
                }
            }
            .onDisappear {
                correctionTask?.cancel()
            }
        }
    }

    private func sendCorrection() {
        let instruction = String(trimmedCorrection.prefix(FoodCorrectionLimit.maxInstructionLength))
        guard !instruction.isEmpty, correctionTask == nil else { return }

        correctionError = nil
        isCorrectionFocused = false
        let snapshot = draft
        let history = correctionHistory
        correctionTask = Task {
            defer { correctionTask = nil }
            do {
                let outcome = try await viewModel.correct(
                    snapshot,
                    instruction: instruction,
                    history: history,
                    mealPeriod: selectedMealPeriod
                )
                try Task.checkCancellation()
                withAnimation(.snappy) {
                    draftsBeforeCorrection.append(snapshot)
                    draft = outcome.result
                    correctedItemIDs = outcome.changedItemIDs
                    correctionHistory.append(
                        FoodCorrectionTurn(instruction: instruction, reply: outcome.reply)
                    )
                }
                correctionText = ""
            } catch is CancellationError {
                return
            } catch {
                correctionError = error.localizedDescription
            }
        }
    }

    /// 回到上一次修正之前的草稿；之后手动做的修改也会一并撤销
    private func undoLastCorrection() {
        guard let previous = draftsBeforeCorrection.popLast() else { return }

        withAnimation(.snappy) {
            draft = previous
            correctedItemIDs = []
            if !correctionHistory.isEmpty {
                correctionHistory.removeLast()
            }
        }
    }
}

private struct CorrectionTurnRow: View {
    let turn: FoodCorrectionTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.instruction)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.brandTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .trailing)

            Label(turn.reply, systemImage: "sparkles")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct FoodItemEditor: View {
    @Binding var item: FoodRecognitionItem
    var isRecentlyCorrected = false
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("食物名称", text: $item.name)
                    .font(.headline)
                if isRecentlyCorrected {
                    PillTag(title: "刚修正", tint: .brandTeal)
                }
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
            }

            TextField("份量描述", text: $item.portionDescription)

            Picker("类别", selection: $item.foodCategory) {
                Text("未选择").tag(FoodCategory?.none)
                ForEach(FoodCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(Optional(category))
                }
            }

            LabeledContent("估计重量") {
                HStack(spacing: 4) {
                    TextField("克", value: $item.estimatedGrams, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                    Text("g")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("热量") {
                HStack(spacing: 4) {
                    TextField("千卡", value: $item.caloriesKcal, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                    Text("千卡")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                NutrientEditor(title: "碳水", value: $item.carbohydratesGrams)
                NutrientEditor(title: "膳食纤维", value: $item.fiberGrams)
            }
            HStack(spacing: 12) {
                NutrientEditor(title: "蛋白质", value: $item.proteinGrams)
                NutrientEditor(title: "脂肪", value: $item.fatGrams)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct NutrientEditor: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.decimalPad)
                Text("g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension FoodRecognitionResult {
    static let empty = FoodRecognitionResult(
        name: "",
        confidence: 0,
        glucoseImpact: "待确认",
        score: 0,
        items: [],
        suggestions: [],
        followUpQuestions: [],
        uncertainties: [],
        provider: "",
        model: "",
        promptVersion: ""
    )
}

private struct PhotoSourceCard: View {
    @Binding var selectedPhotoItems: [PhotosPickerItem]

    let maxSelectionCount: Int

    let isLoading: Bool
    let onCameraTap: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.brandTeal)
                .frame(width: 88, height: 88)
                .background(Color.brandTeal.opacity(0.12), in: Circle())

            VStack(spacing: 8) {
                Text("拍摄你的餐食")
                    .font(.title3.weight(.semibold))
                Text("可以直接拍照，或从图库选择最多 \(maxSelectionCount) 张同一餐的照片。上传前可以补充份量、做法和配料。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isLoading {
                ProgressView("正在读取照片…")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
#if os(iOS)
                    Button(action: onCameraTap) {
                        Label("拍照", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
#endif

                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: maxSelectionCount,
                        selectionBehavior: .ordered,
                        matching: .images
                    ) {
                        Label("从图库选择", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ContextPromptCard: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("上传前补充食物信息", systemImage: "text.bubble")
                .font(.headline)
            Text("描述份量、烹饪方式、酱汁或照片中看不出的配料，可以帮助模型减少猜测。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: onContinue) {
                Label("描述食物并开始识别", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AnalysisProgressCard: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct UserFoodContextCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("你的补充", systemImage: "person.text.rectangle")
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.brandTeal.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct InlineIssueCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Color.brandRose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.brandRose.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PhotoActionRow: View {
    @Binding var selectedPhotoItems: [PhotosPickerItem]

    let maxSelectionCount: Int

    let onCameraTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
#if os(iOS)
            Button(action: onCameraTap) {
                Label("重新拍摄", systemImage: "camera.rotate")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
#endif

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: maxSelectionCount,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Label("更换照片", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular)
    }
}

/// 补充信息页顶部的照片缩略图；至少保留一张，所以只有多张时才能删除
private struct ContextPhotoStrip: View {
    let photos: [Data]
    let onRemove: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                    SelectedPhotoImage(data: data)
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottomLeading) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(.black.opacity(0.5), in: Circle())
                                .padding(5)
                        }
                        .overlay(alignment: .topTrailing) {
                            if photos.count > 1 {
                                Button("删除第 \(index + 1) 张", systemImage: "xmark.circle.fill") {
                                    onRemove(index)
                                }
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .buttonStyle(.plain)
                                .padding(3)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("第 \(index + 1) 张照片")
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct CameraPreviewCard: View {
    let photos: [Data]
    let title: String
    let stateText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MealPhotoPager(photos: photos) { data in
                    SelectedPhotoImage(data: data)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .accessibilityLabel("已选择的餐食照片")
                }

                LinearGradient(
                    colors: [
                        .black.opacity(0.06),
                        .black.opacity(0.18),
                        .black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                ScanFrame()
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .padding(15)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(stateText)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "camera.viewfinder")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.28), in: Circle())
                    }
                    .padding(24)
                }
                // 让左右滑动切换照片的手势穿过文字和取景框
                .allowsHitTesting(false)
            }
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct SelectedPhotoImage: View {
    let data: Data

    var body: some View {
#if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            invalidImagePlaceholder
        }
#elseif os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            invalidImagePlaceholder
        }
#else
        invalidImagePlaceholder
#endif
    }

    private var invalidImagePlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "photo.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

#if os(iOS)
private struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let onImageSelected: (UIImage) -> Void
    var onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel?()
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageSelected(image)
            }

            parent.dismiss()
        }
    }
}
#endif

private struct ScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 38
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private struct RecognitionSummaryCard: View {
    let result: FoodRecognitionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.name)
                        .font(.title3.weight(.semibold))
                    Text("预计 \(result.caloriesText) · 碳水 \(result.carbohydratesText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ScanScoreBadge(score: result.effectiveScore)
            }

            FlowLayout(spacing: 8) {
                ForEach(result.ingredients, id: \.self) { ingredient in
                    PillTag(title: ingredient, tint: Color.brandTeal)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NutritionGrid: View {
    let result: FoodRecognitionResult

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NutritionMetric(title: "碳水", value: result.carbohydratesText, icon: "leaf", tint: Color.brandTeal)
            NutritionMetric(title: "蛋白质", value: result.proteinText, icon: "bolt.heart", tint: Color.brandLeaf)
            NutritionMetric(title: "脂肪", value: result.fatText, icon: "drop", tint: Color.brandAmber)
            NutritionMetric(title: "血糖影响", value: result.effectiveGlucoseImpact, icon: "waveform.path.ecg", tint: Color.brandRose)
        }
    }
}

private struct StableScoreCard: View {
    let result: FoodRecognitionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("稳糖分怎么来的", systemImage: "function")
                .font(.headline)

            if let breakdown = result.stableScore {
                ScoreRow(title: "基础分", detail: "整餐 GL \(breakdown.glycemicLoad.oneDecimalText)", value: breakdown.baseScore, sign: "")
                ScoreRow(title: "蔬菜", detail: "每餐 \(Int(StableScoreCalculator.vegetableTargetGrams)) 克满分", value: breakdown.vegetableBonus, sign: "+")
                ScoreRow(title: "蛋白质", detail: "每餐 \(Int(StableScoreCalculator.proteinTargetGrams)) 克满分", value: breakdown.proteinBonus, sign: "+")
                ScoreRow(title: "全谷物", detail: "占主食 1/3 以上", value: breakdown.wholeGrainBonus, sign: "+")
                ScoreRow(title: "添加糖", detail: "每克扣 \(StableScoreCalculator.addedSugarPenaltyPerGram.oneDecimalText) 分", value: breakdown.addedSugarPenalty, sign: "−")
                Divider()
                LabeledContent("稳糖分") {
                    Text("\(breakdown.score)")
                        .font(.headline)
                        .foregroundStyle(Color.brandLeaf)
                }
            } else {
                Text("这次识别结果缺少食物类别，稳糖分为 AI 估算，仅供参考。可以在「检查并修改识别结果」中为每样食物选择类别。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                StableScoreMethodView()
            } label: {
                Label("评分依据", systemImage: "book.closed")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ScoreRow: View {
    let title: String
    let detail: String
    let value: Double
    let sign: String

    var body: some View {
        LabeledContent {
            Text("\(sign)\(value.oneDecimalText)")
                .monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension StableScoreBreakdown {
    var summaryText: String {
        "基础 \(baseScore.oneDecimalText) + 蔬菜 \(vegetableBonus.oneDecimalText) + 蛋白质 \(proteinBonus.oneDecimalText)"
            + " + 全谷物 \(wholeGrainBonus.oneDecimalText) − 添加糖 \(addedSugarPenalty.oneDecimalText)"
            + " · 整餐 GL \(glycemicLoad.oneDecimalText)（\(glucoseImpact)）"
    }
}

private extension Double {
    var oneDecimalText: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct NutritionMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SuggestionListCard: View {
    let suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("稳糖建议", systemImage: "sparkles")
                .font(.headline)

            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandLeaf)
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct UncertaintyListCard: View {
    let uncertainties: [String]
    let questions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("需要你确认", systemImage: "questionmark.bubble")
                .font(.headline)

            ForEach(uncertainties, id: \.self) { uncertainty in
                Label(uncertainty, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(questions, id: \.self) { question in
                Label(question, systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.brandAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ScanScoreBadge: View {
    let score: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.title3.weight(.bold))
            Text("稳糖分")
                .font(.caption2)
        }
        .foregroundStyle(Color.brandLeaf)
        .frame(width: 62, height: 54)
        .background(Color.brandLeaf.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

#if DEBUG
@MainActor
private func makeFoodScanPreviewViewModel(
    dependencies: AppDependencies,
    phase: FoodScanPhase,
    includesPhoto: Bool = true,
    photoCount: Int = 1,
    includesResult: Bool = false,
    userFoodContext: String = ""
) -> FoodScanViewModel {
    let viewModel = FoodScanViewModel(
        analysisService: dependencies.foodAnalysisService,
        mealRepository: dependencies.mealRepository,
        photoStore: dependencies.mealPhotoStore
    )

    if includesPhoto {
        viewModel.selectedPhotos = Array(repeating: foodScanPreviewPhotoData(), count: photoCount)
    }
    if includesResult {
        viewModel.result = foodScanPreviewResult()
    }

    viewModel.userFoodContext = userFoodContext
    viewModel.phase = phase
    return viewModel
}

private func foodScanPreviewPhotoData() -> Data {
#if canImport(UIKit)
    UIImage(named: "ScanFoodSample")?.jpegData(compressionQuality: 0.9) ?? Data()
#elseif os(macOS)
    NSImage(named: NSImage.Name("ScanFoodSample"))?.tiffRepresentation ?? Data()
#else
    Data()
#endif
}

private func foodScanPreviewResult() -> FoodRecognitionResult {
    FoodRecognitionResult(
        name: "鸡胸藜麦沙拉",
        confidence: 0.92,
        glucoseImpact: "中等",
        score: 82,
        items: [
            FoodRecognitionItem(
                name: "鸡胸肉",
                portionDescription: "约一掌大小",
                estimatedGrams: 120,
                caloriesKcal: 198,
                carbohydratesGrams: 0,
                proteinGrams: 32,
                fatGrams: 7,
                fiberGrams: 0,
                confidence: 0.94,
                evidence: "根据照片中的外观和份量估算"
            ),
            FoodRecognitionItem(
                name: "藜麦",
                portionDescription: "约半碗",
                estimatedGrams: 100,
                caloriesKcal: 120,
                carbohydratesGrams: 21,
                proteinGrams: 4,
                fatGrams: 2,
                fiberGrams: 3,
                confidence: 0.84,
                evidence: "结合照片和用户补充信息估算",
                uncertainties: ["无法仅凭照片确认实际重量"]
            ),
            FoodRecognitionItem(
                name: "蔬菜与牛油果",
                portionDescription: "约一碗",
                estimatedGrams: 180,
                caloriesKcal: 132,
                carbohydratesGrams: 24,
                proteinGrams: 4,
                fatGrams: 9,
                fiberGrams: 8,
                confidence: 0.79,
                evidence: "根据照片中可见的食材估算",
                uncertainties: ["酱汁与烹饪用油不可见"]
            )
        ],
        suggestions: [
            "确认酱汁和主食份量后，碳水估算会更可靠。",
            "蛋白质较充足，可以先吃鸡胸肉和蔬菜再吃主食。"
        ],
        followUpQuestions: ["沙拉中是否添加了含糖酱汁？"],
        uncertainties: ["无法从单张照片确认隐藏的油、糖和全部配料。"],
        provider: "demo",
        model: "food-analysis-demo-v1",
        promptVersion: "food-analysis-v1"
    )
}

#Preview("1 · 选择照片") {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        FoodScanDemoView(
            previewViewModel: makeFoodScanPreviewViewModel(
                dependencies: dependencies,
                phase: .idle,
                includesPhoto: false
            )
        )
    }
    .modelContainer(dependencies.modelContainer)
}

#Preview("2 · 等待补充信息") {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        FoodScanDemoView(
            previewViewModel: makeFoodScanPreviewViewModel(
                dependencies: dependencies,
                phase: .awaitingContext,
                photoCount: 3
            )
        )
    }
    .modelContainer(dependencies.modelContainer)
}

#Preview("3 · 补充食物信息") {
    let dependencies = AppDependencies.preview()
    FoodContextSheet(
        viewModel: makeFoodScanPreviewViewModel(
            dependencies: dependencies,
            phase: .awaitingContext,
            photoCount: 3,
            userFoodContext: "鸡肉清炒，沙拉酱只放了一半。"
        ),
        appendedPhotoItems: .constant([]),
        isLoadingPhoto: false,
        onTakePhoto: {}
    )
    .modelContainer(dependencies.modelContainer)
}

#Preview("4 · 正在优化照片") {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        FoodScanDemoView(
            previewViewModel: makeFoodScanPreviewViewModel(
                dependencies: dependencies,
                phase: .preparingImage
            )
        )
    }
    .modelContainer(dependencies.modelContainer)
}

#Preview("5 · 正在识别") {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        FoodScanDemoView(
            previewViewModel: makeFoodScanPreviewViewModel(
                dependencies: dependencies,
                phase: .analyzing,
                userFoodContext: "鸡肉清炒，沙拉酱只放了一半。"
            )
        )
    }
    .modelContainer(dependencies.modelContainer)
}

#Preview("6 · 识别结果") {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        FoodScanDemoView(
            previewViewModel: makeFoodScanPreviewViewModel(
                dependencies: dependencies,
                phase: .needsReview,
                includesResult: true,
                userFoodContext: "鸡肉清炒，沙拉酱只放了一半。"
            )
        )
    }
    .modelContainer(dependencies.modelContainer)
}

#Preview("7 · 检查并修改") {
    let dependencies = AppDependencies.preview()
    FoodReviewSheet(
        viewModel: makeFoodScanPreviewViewModel(
            dependencies: dependencies,
            phase: .needsReview,
            includesResult: true,
            userFoodContext: "鸡肉清炒，沙拉酱只放了一半。"
        )
    )
    .modelContainer(dependencies.modelContainer)
}

#Preview("8 · 已保存") {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        FoodScanDemoView(
            previewViewModel: makeFoodScanPreviewViewModel(
                dependencies: dependencies,
                phase: .saved,
                includesResult: true,
                userFoodContext: "鸡肉清炒，沙拉酱只放了一半。"
            )
        )
    }
    .modelContainer(dependencies.modelContainer)
}
#endif
