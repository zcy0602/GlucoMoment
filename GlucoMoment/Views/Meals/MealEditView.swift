//
//  MealEditView.swift
//  GlucoMoment
//

import SwiftUI

/// 编辑一条已保存的餐食，以 sheet 呈现。沿用识别结果页的版式：点食物修改、一句话修正、
/// 稳糖分实时重算；照片沿用已保存的版本，不提供换照片和重新识别
struct MealEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FoodScanViewModel
    @State private var isConfirmingDiscard = false
    @State private var savedCount = 0
    let onSaved: (MealRecord) -> Void

    init(
        meal: MealRecord,
        photos: [Data],
        dependencies: AppDependencies,
        onSaved: @escaping (MealRecord) -> Void
    ) {
        _viewModel = State(initialValue: FoodScanViewModel(
            editing: meal,
            photos: photos,
            analysisService: dependencies.foodAnalysisService,
            mealRepository: dependencies.mealRepository,
            photoStore: dependencies.mealPhotoStore
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            MealResultContent(viewModel: viewModel)
                .navigationTitle("编辑这一餐")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .tint(Color.brandTeal)
        .interactiveDismissDisabled(viewModel.hasUnsavedEdits || viewModel.isBusy)
        .confirmationDialog("放弃修改？", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("这次做的修改都不会保存。")
        }
        .onChange(of: viewModel.phase) { _, phase in
            guard phase == .saved, let meal = viewModel.savedMeal else { return }
            savedCount += 1
            onSaved(meal)
            dismiss()
        }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) {
                if viewModel.hasUnsavedEdits {
                    isConfirmingDiscard = true
                } else {
                    dismiss()
                }
            }
            .disabled(viewModel.phase == .saving)
        }

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

    private var canSave: Bool {
        guard let result = viewModel.result, !viewModel.isBusy, viewModel.hasUnsavedEdits else { return false }
        return !result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.items.isEmpty
    }
}
