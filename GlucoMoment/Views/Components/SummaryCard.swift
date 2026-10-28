//
//  SummaryCard.swift
//  GlucoMoment
//

import SwiftUI

/// 「健康」App 摘要页式的卡片：彩色的类别标题，右侧是时间或数量，可带箭头表示能点开
struct SummaryCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    var detail: String?
    var showsChevron = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
        .cardBackground()
    }
}

/// 大号数值加单位，例如「6.8 mmol/L」。数字用圆体，与「健康」App 一致
struct MetricValueText: View {
    let value: String
    let unit: String
    var style: Font.TextStyle = .largeTitle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(style, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// 「设置」App 式的彩色方块图标
struct IconBadge: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 页面中的小节标题，比 List 的 Section 标题更醒目，用在卡片式页面里
struct CardSectionTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            SummaryCard(title: "血糖", systemImage: "drop.fill", tint: .glucoseTint, detail: "10:24", showsChevron: true) {
                MetricValueText(value: "6.8", unit: "mmol/L")
            }
            HStack {
                IconBadge(systemImage: "heart.fill", tint: .pink)
                IconBadge(systemImage: "sparkles", tint: .insightTint)
            }
            CardSectionTitle("今日饮食", trailing: "3 餐")
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
