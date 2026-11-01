//
//  AppSettingsView.swift
//  GlucoMoment
//

import SwiftUI

struct AppSettingsView: View {
    let healthKitCoordinator: HealthKitCoordinator
    let foodAnalysisSettings: FoodAnalysisSettings
    let foodAnalysisCredentialStore: any FoodAnalysisCredentialStoring
    let mealReviewSettings: MealReviewSettings
    let mealReviewCache: any MealReviewCacheStoring

    @State private var isShowingReviewConsent = false
    @AppStorage(InterfacePreference.redesignKey) private var usesRedesign = true

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(healthKitCoordinator.statusText)
                        .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("血糖与饮食同步", systemImage: "heart.text.square")
                }

                Button {
                    Task { await healthKitCoordinator.authorizeAndSync() }
                } label: {
                    if healthKitCoordinator.isSyncing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在同步…")
                        }
                    } else {
                        Label("请求访问并同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(
                    healthKitCoordinator.isSyncing
                        || !healthKitCoordinator.isHealthDataAvailable
                )
            } header: {
                Text("健康 App")
            } footer: {
                Text("稳糖食刻读取最近 30 天的血糖与 5 项饮食营养，并写入本 App 创建的记录。若曾拒绝，请在健康 App 中调整权限后再同步。")
            }

            Section("功能设置") {
                NavigationLink {
                    FoodAnalysisSettingsView(
                        settings: foodAnalysisSettings,
                        credentialStore: foodAnalysisCredentialStore
                    )
                } label: {
                    Label("AI 食物识别", systemImage: "sparkles")
                }
            }

            Section {
                Toggle(isOn: reviewEnabledBinding) {
                    Label("AI 复盘", systemImage: "text.magnifyingglass")
                }
            } header: {
                Text("近期复盘")
            } footer: {
                Text("开启后，趋势页会出现「近期复盘」：把最近 14 天的餐后血糖摘要交给当前的识别服务，写出可以用血糖验证的小建议，不发送照片。关闭时会删除本机保存的复盘。")
            }

            if InterfacePreference.allowsLegacyDesign {
                Section("界面") {
                    Toggle(isOn: $usesRedesign) {
                        Label("使用新版界面", systemImage: "sparkles.rectangle.stack")
                    }
                }
            }

            Section("数据说明") {
                Label("HealthKit 同步副本与手动记录保存在本机 SwiftData 数据库中。", systemImage: "internaldrive")
                Label("本 App 创建的血糖或饮食记录会双向同步；其他来源的记录需在原始 App 中修改或删除。", systemImage: "arrow.left.arrow.right")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingReviewConsent) {
            MealReviewConsentView(destination: foodAnalysisSettings.reviewDestinationDescription) {
                mealReviewSettings.isEnabled = true
            }
        }
    }

    /// 打开时先看数据发送说明，同意后才真正开启；关闭时删除本机保存的复盘
    private var reviewEnabledBinding: Binding<Bool> {
        Binding {
            mealReviewSettings.isEnabled
        } set: { isOn in
            if isOn {
                isShowingReviewConsent = true
            } else {
                mealReviewSettings.isEnabled = false
                Task { await mealReviewCache.clear() }
            }
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        AppSettingsView(
            healthKitCoordinator: dependencies.healthKitCoordinator,
            foodAnalysisSettings: dependencies.foodAnalysisSettings,
            foodAnalysisCredentialStore: dependencies.foodAnalysisCredentialStore,
            mealReviewSettings: dependencies.mealReviewSettings,
            mealReviewCache: dependencies.mealReviewCache
        )
    }
}
