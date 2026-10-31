//
//  RedesignTheme.swift
//  GlucoMoment
//

import SwiftUI

/// 新版界面的语义色。参考「健康」App：每类数据固定一种颜色，用在卡片标题、图标和图表上，
/// 让人不读文字也能分清在看什么。
extension Color {
    /// 血糖
    static let glucoseTint = Color.brandTeal
    /// 饮食
    static let mealTint = Color(red: 0.20, green: 0.64, blue: 0.32)
    /// AI 复盘与稳糖建议
    static let insightTint = Color(red: 0.40, green: 0.36, blue: 0.88)
    /// 图表里的目标范围底色
    static let targetBandFill = Color.green.opacity(0.12)

    /// 稳糖分的颜色。分界与基础分曲线一致：GL < 10 对应 85 分以上，GL 10～20 对应 70～85 分
    static func stableScore(_ score: Int?) -> Color {
        guard let score else { return .secondary }
        switch score {
        case 85...: return Color(red: 0.20, green: 0.68, blue: 0.36)
        case 70..<85: return Color(red: 0.52, green: 0.72, blue: 0.18)
        case 55..<70: return Color.brandAmber
        default: return Color(red: 0.93, green: 0.42, blue: 0.27)
        }
    }
}

extension GlucoseTargetRange {
    /// 血糖曲线的分段着色：低于下限红色、高于上限橙色、范围内用血糖色，在越界处直接切换颜色。
    /// 用在 `LineMark` / `BarMark` 上时要加 `.alignsMarkStylesWithPlotArea()`，让渐变按整个绘图区对齐；
    /// `yDomain` 必须和图表的 `chartYScale(domain:)` 一致，否则分界会错位
    func curveGradient(yDomain: ClosedRange<Double>) -> LinearGradient {
        let span = max(yDomain.upperBound - yDomain.lowerBound, 0.001)
        func location(_ value: Double) -> CGFloat {
            CGFloat(min(max((value - yDomain.lowerBound) / span, 0), 1))
        }
        let low = location(lowerBound)
        let high = location(upperBound)
        let lowTint = GlucoseState.low.tint
        let highTint = GlucoseState.elevated.tint
        return LinearGradient(
            stops: [
                .init(color: lowTint, location: 0),
                .init(color: lowTint, location: low),
                .init(color: .glucoseTint, location: low),
                .init(color: .glucoseTint, location: high),
                .init(color: highTint, location: high),
                .init(color: highTint, location: 1)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    /// 单个点（例如餐后峰值）的颜色，与 `curveGradient` 一致
    func curveTint(for value: Double) -> Color {
        switch state(for: value) {
        case .low: GlucoseState.low.tint
        case .inRange: .glucoseTint
        case .elevated: GlucoseState.elevated.tint
        }
    }
}

extension View {
    /// 新版界面统一的卡片底：分组背景上的圆角块
    func cardBackground(padding: CGFloat = 16) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
    }

    /// 带渐变的卡片底，沿用旧版今日页血糖卡：浅色是白 → 薄荷绿，深色是卡片灰 → 暗青。
    /// 用在每页最上面那张卡，让它比下面的卡更醒目
    func gradientCardBackground(padding: CGFloat = 16) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(CardGradient(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct CardGradient: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> LinearGradient {
        let colors: [Color] = environment.colorScheme == .dark
            ? [Color(.secondarySystemGroupedBackground), Color.brandTeal.opacity(0.32)]
            : [.white, Color.brandMint.opacity(0.75)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 新版界面的数字格式。营养素取整，血糖保留一位小数
nonisolated enum DisplayFormat {
    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func glucose(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// 带正负号的血糖变化，例如「+2.4」
    static func glucoseChange(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
    }

    static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
