//
//  GlucoseEntryView.swift
//  GlucoMoment
//

import SwiftUI

struct GlucoseEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GlucoseEntryViewModel

    let onSaved: () -> Void

    init(
        repository: any GlucoseRepository,
        reading: GlucoseReading?,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: GlucoseEntryViewModel(repository: repository, reading: reading))
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section("血糖值") {
                    HStack(alignment: .firstTextBaseline) {
                        TextField(
                            "例如 6.2",
                            value: $viewModel.value,
                            format: .number.precision(.fractionLength(1))
                        )
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("血糖值，单位 mmol/L")

                        Text("mmol/L")
                            .foregroundStyle(.secondary)
                    }

                    if let validationMessage = viewModel.validationMessage,
                       viewModel.value != nil {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.brandRose)
                    }
                }

                Section("记录时间") {
                    DatePicker(
                        "测量时间",
                        selection: $viewModel.measuredAt,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("备注（可选）") {
                    TextField("例如：午餐后 2 小时", text: $viewModel.note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Text("目标范围暂按 3.9–10.0 mmol/L 展示。本 App 用于记录与回顾，不替代医生诊断或治疗建议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(viewModel.isEditing ? "编辑血糖" : "记录血糖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(!viewModel.canSave)
                }
            }
            .alert("无法保存", isPresented: $viewModel.isShowingError) {
            } message: {
                Text(viewModel.errorMessage ?? "请检查输入后重试。")
            }
        }
    }

    private func save() {
        guard viewModel.save() else { return }
        onSaved()
        dismiss()
    }
}
