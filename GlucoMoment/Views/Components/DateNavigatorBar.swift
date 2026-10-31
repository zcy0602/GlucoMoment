//
//  DateNavigatorBar.swift
//  GlucoMoment
//

import SwiftUI

/// 日期切换行：左边日历图标 + 当前日期或时间段，点按弹出日历；右边「今天」和前后翻页。
/// 血糖页和血糖记录页共用，版式与饮食页的日期行一致
struct DateNavigatorBar: View {
    let title: String
    /// 翻页按钮的读屏文字，例如「一天」「7 天」
    let pageLabel: String
    let isShowingToday: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    var titleHint = "选择要查看的日期"
    let onTapTitle: () -> Void
    let onToday: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTapTitle) {
                // 不用 Label：它的图标和文字间距偏大
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(title)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandTeal)
                .contentTransition(.numericText())
            }
            .buttonStyle(.borderless)
            .accessibilityHint(titleHint)

            Spacer(minLength: 8)

            Button("今天") {
                withAnimation(.snappy) { onToday() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .tint(Color.brandTeal)
            .disabled(isShowingToday)
            .padding(.trailing, 6)

            pageButton("chevron.left", label: "前\(pageLabel)", enabled: canGoBack, action: onPrevious)
            pageButton("chevron.right", label: "后\(pageLabel)", enabled: canGoForward, action: onNext)
        }
        .padding(.horizontal, 4)
    }

    private func pageButton(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: systemImage) {
            withAnimation(.snappy) { action() }
        }
        .labelStyle(.iconOnly)
        .font(.subheadline.weight(.semibold))
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .buttonStyle(.borderless)
        .tint(Color.brandTeal)
        .disabled(!enabled)
    }
}
