//
//  SettingsView.swift
//  GlucoMoment
//

import SwiftUI

/// 新版设置，从「今天」右上角进入。版式参考「设置」App：每行一个彩色图标，说明文字放在分组脚注里
struct SettingsView: View {
    let dependencies: AppDependencies

    @Environment(\.dismiss) private var dismiss
    @AppStorage(InterfacePreference.redesignKey) private var usesRedesign = true
    @State private var isShowingReviewConsent = false

    private var healthKit: HealthKitCoordinator { dependencies.healthKitCoordinator }
    private var reviewSettings: MealReviewSettings { dependencies.mealReviewSettings }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconBadge(systemImage: "heart.fill", tint: .pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("健康 App")
                        Text(healthKit.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                    }
                    Spacer()
                    if healthKit.isSyncing {
                        ProgressView()
                    } else {
                        Button("同步") {
                            Task { await healthKit.authorizeAndSync() }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .disabled(!healthKit.isHealthDataAvailable)
                    }
                }
            } footer: {
                Text("读取最近 30 天的血糖和饮食营养，并把在这里记录的内容写回健康 App。")
            }

            Section {
                NavigationLink {
                    FoodAnalysisSettingsView(
                        settings: dependencies.foodAnalysisSettings,
                        credentialStore: dependencies.foodAnalysisCredentialStore
                    )
                } label: {
                    row(icon: "camera.viewfinder", tint: .mealTint, title: "食物识别") {
                        Text(dependencies.foodAnalysisSettings.mode.title)
                    }
                }

                Toggle(isOn: reviewEnabledBinding) {
                    row(icon: "sparkles", tint: .insightTint, title: "AI 复盘") { EmptyView() }
                }
            } header: {
                Text("AI")
            } footer: {
                Text("AI 复盘会把最近 14 天的餐后血糖摘要发给当前的识别服务，不发送照片。关闭时删除本机保存的复盘。")
            }

            Section {
                NavigationLink {
                    ScoreMethodView()
                } label: {
                    row(icon: "function", tint: .brandTeal, title: "稳糖分怎么算") { EmptyView() }
                }
                NavigationLink {
                    DataStatementView()
                } label: {
                    row(icon: "lock.fill", tint: .gray, title: "数据与隐私") { EmptyView() }
                }
            }

            Section {
                Toggle(isOn: $usesRedesign) {
                    row(icon: "rectangle.on.rectangle", tint: .indigo, title: "使用新版界面") { EmptyView() }
                }
            } footer: {
                Text("关闭后回到旧版界面，可随时在设置里切换回来。")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { dismiss() }
            }
        }
        .sheet(isPresented: $isShowingReviewConsent) {
            MealReviewConsentView(destination: dependencies.foodAnalysisSettings.reviewDestinationDescription) {
                reviewSettings.isEnabled = true
            }
        }
    }

    private func row<Trailing: View>(
        icon: String,
        tint: Color,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: icon, tint: tint)
            Text(title)
            Spacer()
            trailing()
                .foregroundStyle(.secondary)
        }
    }

    /// 打开时先看数据发送说明，同意后才真正开启；关闭时删除本机保存的复盘
    private var reviewEnabledBinding: Binding<Bool> {
        Binding {
            reviewSettings.isEnabled
        } set: { isOn in
            if isOn {
                isShowingReviewConsent = true
            } else {
                reviewSettings.isEnabled = false
                Task { await dependencies.mealReviewCache.clear() }
            }
        }
    }
}

/// 数据保存在哪里、会发给谁
private struct DataStatementView: View {
    var body: some View {
        List {
            Section {
                Label("血糖、饮食记录和照片只保存在这台 iPhone 上。", systemImage: "iphone")
                Label("在本 App 里创建的记录会同步到健康 App；其他来源的记录只读，需要在原来的 App 里修改。", systemImage: "arrow.left.arrow.right")
            } header: {
                Text("保存")
            }

            Section {
                Label("识别一餐时，压缩后的照片和你的补充说明会发给所选的识别服务，照片的位置等信息会先移除。", systemImage: "camera.viewfinder")
                Label("只有开启 AI 复盘后，才会发送餐后血糖摘要；健康数据不会用于食物识别。", systemImage: "sparkles")
                Label("自定义 API 的 Key 保存在系统钥匙串中。", systemImage: "key.fill")
            } header: {
                Text("发送")
            }
        }
        .font(.subheadline)
        .navigationTitle("数据与隐私")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        SettingsView(dependencies: dependencies)
    }
}
