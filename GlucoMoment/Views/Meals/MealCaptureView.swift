//
//  MealCaptureView.swift
//  GlucoMoment
//

import PhotosUI
import SwiftUI
import UIKit

/// 记录一餐的完整流程，以 sheet 呈现：补充说明 → 识别中 → 检查结果并保存。
/// 状态都在 `FoodScanViewModel` 里，这里只按阶段切换内容和工具栏
struct MealCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FoodScanViewModel
    /// 识别出结果后为 true；之后保存失败时仍停留在结果页，而不是回到失败页
    @State private var isReviewingResult = false
    @State private var addSource: MealPhotoSource?
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var isConfirmingDiscard = false
    @State private var savedCount = 0
    let onSaved: () -> Void

    init(photos: [Data], dependencies: AppDependencies, onSaved: @escaping () -> Void) {
        let viewModel = FoodScanViewModel(
            analysisService: dependencies.foodAnalysisService,
            mealRepository: dependencies.mealRepository,
            photoStore: dependencies.mealPhotoStore
        )
        viewModel.selectPhotos(photos)
        _viewModel = State(initialValue: viewModel)
        self.onSaved = onSaved
    }

#if DEBUG
    /// 仅供 Preview 直接展示某个阶段
    init(previewViewModel: FoodScanViewModel) {
        _viewModel = State(initialValue: previewViewModel)
        _isReviewingResult = State(initialValue: previewViewModel.result != nil)
        onSaved = {}
    }
#endif

    private enum Step: Equatable {
        case compose
        case analyzing
        case failed(String)
        case result
    }

    private var step: Step {
        switch viewModel.phase {
        case .idle, .awaitingContext:
            .compose
        case .preparingImage, .analyzing:
            .analyzing
        case .failed(let message):
            isReviewingResult && viewModel.result != nil ? .result : .failed(message)
        case .needsReview, .saving, .saved:
            .result
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .compose:
                    MealComposeContent(viewModel: viewModel) { source in
                        addSource = source
                    }
                case .analyzing:
                    MealAnalyzingContent(
                        photos: viewModel.selectedPhotos,
                        statusText: viewModel.scanStateText
                    )
                case .failed(let message):
                    failureContent(message)
                case .result:
                    MealResultContent(viewModel: viewModel)
                }
            }
            .animation(.smooth, value: step)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .tint(Color.brandTeal)
        .interactiveDismissDisabled(viewModel.result != nil || viewModel.isBusy)
        .confirmationDialog("放弃这条记录？", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("识别结果和你做的修改都不会保存。")
        }
        .onChange(of: viewModel.phase) { _, phase in
            switch phase {
            case .needsReview:
                isReviewingResult = true
            case .saved:
                savedCount += 1
                onSaved()
                dismiss()
            default:
                break
            }
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .onChange(of: addSource) { _, source in
            guard let source else { return }
            addSource = nil
            switch source {
            case .camera:
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isShowingCamera = true
                }
            case .library:
                isShowingLibrary = true
            }
        }
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $libraryItems,
            maxSelectionCount: max(viewModel.remainingPhotoSlots, 1),
            selectionBehavior: .ordered,
            matching: .images
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                if let photos = try? await PhotoLoading.load(items) {
                    withAnimation(.snappy) { viewModel.addPhotos(photos) }
                }
                libraryItems = []
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCaptureView { data in
                withAnimation(.snappy) { viewModel.addPhotos([data]) }
            }
            .ignoresSafeArea()
        }
        .onDisappear {
            viewModel.cancelAnalysis()
        }
    }

    private var title: String {
        switch step {
        case .compose: "新的一餐"
        case .analyzing: "正在识别"
        case .failed: "识别未完成"
        case .result: "检查这一餐"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) {
                if viewModel.result != nil {
                    isConfirmingDiscard = true
                } else {
                    dismiss()
                }
            }
        }

        if step == .result {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("修改照片和说明", systemImage: "photo.on.rectangle") {
                        isReviewingResult = false
                        viewModel.phase = .awaitingContext
                    }
                    Button("重新识别", systemImage: "arrow.clockwise") {
                        viewModel.startAnalysis()
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                }
                .disabled(viewModel.isBusy)
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .confirmationAction) {
                if viewModel.phase == .saving {
                    ProgressView()
                } else {
                    Button("保存", systemImage: "checkmark") {
                        Task { await viewModel.save() }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        guard let result = viewModel.result, !viewModel.isBusy else { return false }
        return !result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.items.isEmpty
    }

    private func failureContent(_ message: String) -> some View {
        ContentUnavailableView {
            Label("没能识别这一餐", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                viewModel.startAnalysis()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button("修改照片和说明") {
                viewModel.phase = .awaitingContext
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 补充说明

/// 第一步：确认照片，补充照片里看不出的信息，然后开始识别
private struct MealComposeContent: View {
    @Bindable var viewModel: FoodScanViewModel
    let onAddPhotos: (MealPhotoSource) -> Void

    @FocusState private var isDescriptionFocused: Bool

    private static let hints = ["份量", "做法", "酱汁与用油", "只吃了一部分", "包装上的营养表"]
    private static let maxContextLength = 500

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                photoSection
                timeSection
                descriptionSection
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                isDescriptionFocused = false
                viewModel.startAnalysis()
            } label: {
                Label("开始识别", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(viewModel.selectedPhotos.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.selectedPhotos.enumerated()), id: \.offset) { index, data in
                        photoTile(data: data, index: index)
                    }
                    if viewModel.remainingPhotoSlots > 0 {
                        addTile
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)

            Text("\(viewModel.selectedPhotos.count) 张照片 · 同一餐的不同菜或角度会一起识别")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func photoTile(data: Data, index: Int) -> some View {
        PhotoDataImage(data: data)
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if viewModel.selectedPhotos.count > 1 {
                    Button("移除第 \(index + 1) 张", systemImage: "xmark") {
                        withAnimation(.snappy) { viewModel.removePhoto(at: index) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(8)
                }
            }
            .transition(.scale.combined(with: .opacity))
    }

    private var addTile: some View {
        Menu {
            Button("拍照", systemImage: "camera") { onAddPhotos(.camera) }
            Button("从相册选择", systemImage: "photo.on.rectangle") { onAddPhotos(.library) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                Text("再加一张")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .frame(width: 150, height: 150)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(.tertiary)
            )
        }
    }

    /// 餐次和时间在识别前就能确认；餐次会随照片一起发给识别服务
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("什么时候吃的")
                .font(.headline)
            MealTimeFields(viewModel: viewModel)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("补充说明")
                    .font(.headline)
                Text("可选")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.userFoodContext.isEmpty {
                    Text("\(viewModel.userFoodContext.count)/\(Self.maxContextLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            TextField(
                "照片里看不出的份量、做法或配料，比如“米饭只吃了半碗”",
                text: $viewModel.userFoodContext,
                axis: .vertical
            )
            .lineLimit(3...8)
            .focused($isDescriptionFocused)
            .padding(14)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .onChange(of: viewModel.userFoodContext) { _, newValue in
                if newValue.count > Self.maxContextLength {
                    viewModel.userFoodContext = String(newValue.prefix(Self.maxContextLength))
                }
            }

            ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Self.hints, id: \.self) { hint in
                    Button {
                        append(hint)
                    } label: {
                        Label(hint, systemImage: "plus")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(.secondary)
                }
            }
        }
    }

    private func append(_ hint: String) {
        let separator = viewModel.userFoodContext.isEmpty ? "" : "\n"
        viewModel.userFoodContext = String((viewModel.userFoodContext + separator + "\(hint)：").prefix(Self.maxContextLength))
        isDescriptionFocused = true
    }
}

// MARK: - 识别中

/// 第二步：照片上扫过一道光，提示正在识别
private struct MealAnalyzingContent: View {
    let photos: [Data]
    let statusText: String

    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 0)

            ZStack {
                if photos.count > 1, let second = photos.dropFirst().first {
                    PhotoDataImage(data: second)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .rotationEffect(.degrees(7))
                        .offset(x: 14, y: 6)
                        .opacity(0.6)
                }

                if let first = photos.first {
                    PhotoDataImage(data: first)
                        .frame(width: 220, height: 220)
                        .overlay {
                            GeometryReader { proxy in
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.65), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 70)
                                .offset(y: isScanning ? proxy.size.height - 20 : -50)
                                .blendMode(.plusLighter)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                }
            }

            VStack(spacing: 8) {
                Label("正在识别食物与营养", systemImage: "sparkles")
                    .font(.headline)
                    .symbolEffect(.pulse)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)

            Text("通常需要 10～30 秒")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isScanning = true
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
func makeMealCapturePreviewViewModel(phase: FoodScanPhase, includesResult: Bool) -> FoodScanViewModel {
    let dependencies = AppDependencies.preview()
    let viewModel = FoodScanViewModel(
        analysisService: dependencies.foodAnalysisService,
        mealRepository: dependencies.mealRepository,
        photoStore: dependencies.mealPhotoStore
    )
    let photo = UIImage(named: "ScanFoodSample")?.jpegData(compressionQuality: 0.9) ?? Data()
    viewModel.selectedPhotos = [photo, photo]
    viewModel.phase = phase
    if includesResult {
        viewModel.result = FoodRecognitionResult(
            name: "鸡胸藜麦沙拉",
            confidence: 0.92,
            glucoseImpact: "中等",
            score: 82,
            items: [
                FoodRecognitionItem(name: "鸡胸肉", portionDescription: "约一掌大小", estimatedGrams: 120, caloriesKcal: 198, carbohydratesGrams: 0, proteinGrams: 32, fatGrams: 7, fiberGrams: 0, confidence: 0.94, evidence: "根据照片中的外观和份量估算", foodCategory: .protein),
                FoodRecognitionItem(name: "藜麦", portionDescription: "约半碗", estimatedGrams: 100, caloriesKcal: 120, carbohydratesGrams: 21, proteinGrams: 4, fatGrams: 2, fiberGrams: 3, confidence: 0.84, evidence: "结合照片和用户补充信息估算", foodCategory: .wholeGrainLegume),
                FoodRecognitionItem(name: "蔬菜与牛油果", portionDescription: "约一碗", estimatedGrams: 180, caloriesKcal: 132, carbohydratesGrams: 24, proteinGrams: 4, fatGrams: 9, fiberGrams: 8, confidence: 0.79, evidence: "根据照片中可见的食材估算", foodCategory: .vegetable)
            ],
            suggestions: [],
            followUpQuestions: ["沙拉中是否添加了含糖酱汁？"],
            uncertainties: ["无法从照片确认隐藏的油、糖和全部配料。"],
            provider: "demo",
            model: "food-analysis-demo-v1",
            promptVersion: "food-analysis-v2"
        )
    }
    return viewModel
}

#Preview("补充说明") {
    MealCaptureView(previewViewModel: makeMealCapturePreviewViewModel(phase: .awaitingContext, includesResult: false))
}

#Preview("识别中") {
    MealCaptureView(previewViewModel: makeMealCapturePreviewViewModel(phase: .analyzing, includesResult: false))
}

#Preview("识别结果") {
    MealCaptureView(previewViewModel: makeMealCapturePreviewViewModel(phase: .needsReview, includesResult: true))
}
#endif
