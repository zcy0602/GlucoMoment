//
//  MealReviewConsentView.swift
//  GlucoMoment
//

import SwiftUI

/// 开启近期复盘前的数据发送说明，趋势页和设置页共用。用户点「同意并开启」才会开启
struct MealReviewConsentView: View {
    @Environment(\.dismiss) private var dismiss
    /// 例如「当前识别方式是自建代理：数据会发送到……」
    let destination: String
    let onAgree: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("开启后，App 会把最近 14 天的餐后血糖摘要交给 AI，写出最多 3 条可以用自己的血糖去验证的小建议。数字都由 App 在本机计算并填入，AI 只负责写话。")
                }

                Section("会发送") {
                    Label("最近 14 天有连续血糖数据的餐（最多 20 餐）：菜名、食物及类别和碳水、稳糖分", systemImage: "fork.knife")
                    Label("每餐的餐后血糖指标（基线、峰值升幅、达峰时间等）和一段每 15 分钟一个点的曲线", systemImage: "waveform.path.ecg")
                    Label("整体统计：读数条数、平均值、范围内记录占比", systemImage: "chart.bar")
                }

                Section("不会发送") {
                    Label("照片、备注、补充描述和带年份的精确时间", systemImage: "eye.slash")
                    Label("完整的原始血糖读数", systemImage: "eye.slash")
                    Label("餐后出现低于 3.9 mmol/L 读数的餐（App 会另外提醒你）", systemImage: "exclamationmark.shield")
                }

                Section("发给谁") {
                    Text(destination)
                }

                Section {
                    Text("复盘仅供饮食记录参考，不是诊断；调整饮食或用药请咨询医生或营养师。可以随时在「设置」中关闭，关闭后会删除本机保存的复盘。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("开启 AI 复盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAgree()
                    dismiss()
                } label: {
                    Text("同意并开启")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }
}

#Preview {
    MealReviewConsentView(destination: FoodAnalysisSettings(mode: .proxy).reviewDestinationDescription) {}
}
