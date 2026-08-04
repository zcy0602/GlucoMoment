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
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var presentedSheet: FoodScanSheet?
    @State private var photoSelectionIssue: PhotoSelectionIssue?
    @State private var isLoadingPhoto = false

    init(
        analysisService: any FoodAnalysisService,
        mealRepository: any MealRepository,
        photoStore: any MealPhotoStoring,
        initialMealPeriod: MealPeriod = .lunch
    ) {
        _viewModel = State(
            initialValue: FoodScanViewModel(
                analysisService: analysisService,
                mealRepository: mealRepository,
                photoStore: photoStore,
                initialMealPeriod: initialMealPeriod
            )
        )
    }

    var body: some View {
        DemoScreen(title: viewModel.title) {
            if let selectedPhotoData = viewModel.selectedPhotoData {
                CameraPreviewCard(
                    photoData: selectedPhotoData,
                    title: viewModel.result?.name ?? "待识别餐食",
                    stateText: viewModel.scanStateText
                )
                PhotoActionRow(
                    selectedPhotoItem: $selectedPhotoItem,
                    onCameraTap: openCamera
                )

                scanContent
            } else {
                PhotoSourceCard(
                    selectedPhotoItem: $selectedPhotoItem,
                    isLoading: isLoadingPhoto,
                    onCameraTap: openCamera
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .camera:
#if os(iOS)
                CameraPicker { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else {
                        photoSelectionIssue = PhotoSelectionIssue(message: "拍摄的照片无法读取，请重试。")
                        return
                    }

                    applySelectedPhoto(data)
                }
#else
                EmptyView()
#endif
            case .context:
                FoodContextSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            case .review:
                FoodReviewSheet(viewModel: viewModel)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }

            Task {
                await loadPhoto(from: newItem)
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

    private func openCamera() {
#if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            photoSelectionIssue = PhotoSelectionIssue(
                message: "当前设备没有可用的相机，可以改从图库选择照片。"
            )
            return
        }

        presentedSheet = .camera
#else
        photoSelectionIssue = PhotoSelectionIssue(message: "当前平台不支持在 App 内拍照。")
#endif
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  !data.isEmpty else {
                throw PhotoLoadingError.invalidData
            }

            applySelectedPhoto(data)
        } catch {
            photoSelectionIssue = PhotoSelectionIssue(
                message: "图库中的照片加载失败，请换一张照片或重试。"
            )
        }
    }

    private func applySelectedPhoto(_ data: Data) {
        withAnimation(.snappy) {
            viewModel.selectPhoto(data)
        }
        presentedSheet = .context
    }
}

private enum FoodScanSheet: String, Identifiable {
    case camera
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

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
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
                    FlowLayout(spacing: 8) {
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

                Section {
                    Button {
                        startAnalysis(skipDescription: false)
                    } label: {
                        Label("开始识别", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("跳过描述并识别") {
                        startAnalysis(skipDescription: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("补充食物信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
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

    init(viewModel: FoodScanViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.result ?? .empty)
        _selectedMealPeriod = State(initialValue: viewModel.selectedMealPeriod)
        _eatenAt = State(initialValue: viewModel.eatenAt)
        _userNote = State(initialValue: viewModel.userNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("餐食信息") {
                    TextField("餐食名称", text: $draft.name)
                    Picker("餐次", selection: $selectedMealPeriod) {
                        ForEach(MealPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    DatePicker("用餐时间", selection: $eatenAt)
                    TextField("备注（可选）", text: $userNote, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach($draft.items) { $item in
                        FoodItemEditor(item: $item) {
                            draft.items.removeAll { $0.id == item.id }
                        }
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
                                evidence: "用户手动添加"
                            )
                        )
                    }
                } header: {
                    Text("食物与营养")
                } footer: {
                    Text("照片识别只能提供估算，请根据实际份量进行调整。")
                }
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
                        dismiss()
                    }
                    .disabled(
                        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.items.isEmpty
                    )
                }
            }
        }
    }
}

private struct FoodItemEditor: View {
    @Binding var item: FoodRecognitionItem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("食物名称", text: $item.name)
                    .font(.headline)
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
            }

            TextField("份量描述", text: $item.portionDescription)

            LabeledContent("估计重量") {
                TextField("克", value: $item.estimatedGrams, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                Text("g")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("热量") {
                TextField("千卡", value: $item.caloriesKcal, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                Text("千卡")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                NutrientEditor(title: "碳水", value: $item.carbohydratesGrams)
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
    @Binding var selectedPhotoItem: PhotosPickerItem?

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
                Text("可以直接拍照，或从图库选择已有照片。上传前可以补充份量、做法和配料。")
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

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
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
    @Binding var selectedPhotoItem: PhotosPickerItem?

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

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("更换照片", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular)
    }
}

private struct CameraPreviewCard: View {
    let photoData: Data
    let title: String
    let stateText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SelectedPhotoImage(data: photoData)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityLabel("已选择的餐食照片")

                LinearGradient(
                    colors: [
                        .black.opacity(0.06),
                        .black.opacity(0.18),
                        .black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ScanFrame()
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .padding(15)

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

                ScanScoreBadge(score: result.score)
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
            NutritionMetric(title: "血糖影响", value: result.glucoseImpact, icon: "waveform.path.ecg", tint: Color.brandRose)
        }
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

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        FoodScanDemoView(
            analysisService: dependencies.foodAnalysisService,
            mealRepository: dependencies.mealRepository,
            photoStore: dependencies.mealPhotoStore
        )
    }
    .modelContainer(dependencies.modelContainer)
}
