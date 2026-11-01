//
//  SettingsView.swift
//  GlucoMoment
//

import SwiftUI

/// 新版设置，从各标签页右上角进入。版式参考「设置」App：每行一个彩色图标，说明文字放在分组脚注里
struct SettingsView: View {
    let dependencies: AppDependencies

    @Environment(\.dismiss) private var dismiss
    @AppStorage(InterfacePreference.redesignKey) private var usesRedesign = true
    @State private var isShowingReviewConsent = false
    @State private var isShowingGlucoseTarget = false

    private var healthKit: HealthKitCoordinator { dependencies.healthKitCoordinator }
    private var reviewSettings: MealReviewSettings { dependencies.mealReviewSettings }
    private var glucoseTarget: GlucoseTargetSettings { dependencies.glucoseTargetSettings }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    // Apple 官方健康 App 图标（developer.apple.com 下载），旁边要写出 Apple 健康（HIG）。
                    // 图标是白底，参照系统「设置」加一圈细描边，否则和白色单元格融在一起
                    Image("Icon - Apple Health")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 30 * 0.27, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 30 * 0.27, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple 健康")
                        // 同步时间和条数各占一行，且每行强制不换行：放不下时略微缩小字号，避免在数字和量词中间断开
                        Group {
                            Text(healthKit.statusHeadline)
                            if let syncedCountText = healthKit.syncedCountText {
                                Text(syncedCountText)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                Button {
                    isShowingGlucoseTarget = true
                } label: {
                    row(icon: "scope", tint: .glucoseTint, title: "血糖目标范围") {
                        Text("\(DisplayFormat.glucose(glucoseTarget.range.lowerBound))–\(DisplayFormat.glucose(glucoseTarget.range.upperBound))")
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
            } footer: {
                Text(glucoseTargetFooter)
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

            if InterfacePreference.allowsLegacyDesign {
                Section {
                    Toggle(isOn: $usesRedesign) {
                        row(icon: "rectangle.on.rectangle", tint: .indigo, title: "使用新版界面") { EmptyView() }
                    }
                } footer: {
                    Text("关闭后回到旧版界面，可随时在设置里切换回来。")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { dismiss() }
            }
        }
        .sheet(isPresented: $isShowingGlucoseTarget) {
            GlucoseTargetView(settings: glucoseTarget, repository: dependencies.glucoseRepository)
                .tint(Color.brandTeal)
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

    private var glucoseTargetFooter: String {
        let status = glucoseTarget.isCustomized ? "已自定义" : "推荐值"
        guard let population = glucoseTarget.population else {
            return glucoseTarget.isCustomized ? "已自定义。用于图表的目标带和「目标范围内」的比例。" : "未设置，按糖尿病成人的推荐范围显示。"
        }
        return "\(population.title)，\(status)。"
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
