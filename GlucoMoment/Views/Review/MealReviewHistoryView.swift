//
//  MealReviewHistoryView.swift
//  GlucoMoment
//

import SwiftUI

/// 本机保存的 AI 复盘，从新到旧排列；左滑删除，点进去看全文
struct MealReviewHistoryView: View {
    let viewModel: MealReviewViewModel

    var body: some View {
        List {
            Section {
                ForEach(viewModel.history) { saved in
                    NavigationLink {
                        HistoryDetail(saved: saved)
                    } label: {
                        HistoryRow(saved: saved, isLatest: saved.id == viewModel.history.first?.id)
                    }
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { viewModel.history[$0].id })
                    Task { await viewModel.deleteReviews(ids: ids) }
                }
            } footer: {
                if !viewModel.history.isEmpty {
                    Text("只保存在本机，最多保留最近 \(SavedMealReview.historyLimit) 份。关闭 AI 复盘时会全部删除。")
                }
            }
        }
        .overlay {
            if viewModel.history.isEmpty {
                ContentUnavailableView(
                    "没有历史复盘",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("在复盘页生成的 AI 复盘会保存在这里。")
                )
            }
        }
        .navigationTitle("历史复盘")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HistoryRow: View {
    let saved: SavedMealReview
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(saved.generatedAt.formatted(GlucoMomentDateStyle.monthDayTime))
                    .font(.headline)
                if isLatest {
                    Text("最新")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.insightTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.insightTint.opacity(0.12), in: Capsule())
                }
            }
            if let coverage = saved.coverageText {
                Text(coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let first = saved.review.items.first {
                Text(first.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryDetail: View {
    let saved: SavedMealReview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MealReviewItemsView(review: saved.review)

                Text(saved.review.originText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    if let coverage = saved.coverageText {
                        Text(coverage)
                    }
                    Text("数字是生成时的计算结果，之后补记或修改的餐不会更新到这里。")
                    Text("仅供参考，不是诊断。调整饮食或用药请咨询医生。")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .cardBackground()
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(saved.generatedAt.formatted(GlucoMomentDateStyle.monthDayTime))
        .navigationBarTitleDisplayMode(.inline)
    }
}
