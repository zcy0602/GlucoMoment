//
//  CarePlanDemoView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

struct CarePlanDemoView: View {
    @State private var viewModel = CarePlanViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: viewModel.title) {
            PlanSummaryCard(goal: viewModel.weeklyGoal, progress: viewModel.progress, progressText: viewModel.progressText)

            Toggle(isOn: $viewModel.reminderEnabled) {
                Label("餐后提醒", systemImage: "bell.and.waves.left.and.right")
            }
            .font(.headline)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            SectionHeader("今日任务")
            VStack(spacing: 10) {
                ForEach(viewModel.tasks) { task in
                    TaskRow(task: task) {
                        viewModel.toggleTask(task)
                    }
                }
            }

            SectionHeader("医生/营养师 Demo 备注")
            PlanNotesCard(notes: viewModel.notes)
        }
    }
}

private struct PlanSummaryCard: View {
    let goal: String
    let progress: Double
    let progressText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本周目标")
                        .font(.headline)
                    Text(goal)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "flag.checkered")
                    .foregroundStyle(Color.brandTeal)
                    .frame(width: 42, height: 42)
                    .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 16))
            }

            ProgressView(value: progress)
                .tint(Color.brandTeal)

            Text(progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TaskRow: View {
    let task: CareTask
    let onToggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy, onToggle)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.brandLeaf : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct PlanNotesCard: View {
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                Label(note, systemImage: noteIcon(for: index))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func noteIcon(for index: Int) -> String {
        switch index {
        case 0:
            "stethoscope"
        case 1:
            "calendar.badge.checkmark"
        default:
            "cross.case"
        }
    }
}

#Preview {
    NavigationStack {
        CarePlanDemoView()
    }
}
