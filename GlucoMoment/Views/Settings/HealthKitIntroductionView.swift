//
//  HealthKitIntroductionView.swift
//  GlucoMoment
//

import SwiftUI

struct HealthKitIntroductionView: View {
    @Environment(\.dismiss) private var dismiss

    let coordinator: HealthKitCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            Image("Icon - Apple Health")
                .resizable()
                .scaledToFit()
                .font(.system(size: 56))
                .foregroundStyle(Color.brandTeal)
                .frame(width: 100, height: 100)
                .shadow(radius: 2)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("连接健康 App")
                    .font(.title.bold())
                Text("授权后，稳糖食刻会在健康 App 与本 App 之间同步血糖和饮食营养记录。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                PermissionDetailRow(
                    systemImage: "drop.fill",
                    title: "血糖双向同步",
                    detail: "读取最近 30 天的血糖；在本 App 新建、修改或删除的血糖也会同步到健康 App。"
                )
                PermissionDetailRow(
                    systemImage: "fork.knife",
                    title: "5 项饮食营养",
                    detail: "同步热量、碳水化合物、蛋白质、总脂肪和膳食纤维，不请求其他营养数据。"
                )
                PermissionDetailRow(
                    systemImage: "hand.raised.fill",
                    title: "由你控制",
                    detail: "你可以在健康 App 中随时调整每一项数据的读写权限。"
                )
            }

            Spacer()

            if coordinator.isHealthDataAvailable {
                Button {
                    Task { await coordinator.authorizeAndSync() }
                } label: {
                    if coordinator.isSyncing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("继续并授权")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(coordinator.isSyncing)
                .accessibilityIdentifier("healthkit-authorize-button")
            } else {
                Text("此设备目前无法使用健康数据，你仍可继续在 App 内记录血糖和饮食。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(coordinator.isHealthDataAvailable ? "暂不使用" : "知道了") {
                coordinator.useWithoutHealthKit()
                dismiss()
            }
            .disabled(coordinator.isSyncing)
            .accessibilityIdentifier("healthkit-not-now-button")
        }
        .padding(24)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}

private struct PermissionDetailRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.brandTeal)
                .frame(width: 38, height: 38)
                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    HealthKitIntroductionView(
        coordinator: HealthKitCoordinator(
            service: UnavailableHealthKitSynchronizationService(),
            presentsIntroduction: false
        )
    )
}
