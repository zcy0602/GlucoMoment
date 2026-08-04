//
//  PersistenceUnavailableView.swift
//  GlucoMoment
//

import SwiftUI

struct PersistenceUnavailableView: View {
    let error: any Error

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("你的数据没有被自动删除。请重新启动 App；如果问题持续，请联系支持人员。")
        }
        .accessibilityHint("错误信息：\(error.localizedDescription)")
    }
}
