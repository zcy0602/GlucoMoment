//
//  AppSettingsView.swift
//  GlucoMoment
//

import SwiftUI

struct AppSettingsView: View {
    let healthKitCoordinator: HealthKitCoordinator
    let foodAnalysisSettings: FoodAnalysisSettings
    let foodAnalysisCredentialStore: any FoodAnalysisCredentialStoring

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

            Section("数据说明") {
                Label("HealthKit 同步副本与手动记录保存在本机 SwiftData 数据库中。", systemImage: "internaldrive")
                Label("本 App 创建的血糖或饮食记录会双向同步；其他来源的记录需在原始 App 中修改或删除。", systemImage: "arrow.left.arrow.right")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        AppSettingsView(
            healthKitCoordinator: dependencies.healthKitCoordinator,
            foodAnalysisSettings: dependencies.foodAnalysisSettings,
            foodAnalysisCredentialStore: dependencies.foodAnalysisCredentialStore
        )
    }
}
