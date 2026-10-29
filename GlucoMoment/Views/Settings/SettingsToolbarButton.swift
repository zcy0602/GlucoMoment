//
//  SettingsToolbarButton.swift
//  GlucoMoment
//

import SwiftUI

/// 三个标签页右上角都有的设置入口，与「健康」App 每页右上角的个人资料按钮一致。
/// 自己持有弹出状态，放进任意页面的工具栏即可
struct SettingsToolbarButton: View {
    let dependencies: AppDependencies

    @State private var isShowingSettings = false

    var body: some View {
        Button("设置", systemImage: "person.crop.circle") {
            isShowingSettings = true
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView(dependencies: dependencies)
            }
            .tint(Color.brandTeal)
        }
    }
}
