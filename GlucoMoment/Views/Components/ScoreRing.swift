//
//  ScoreRing.swift
//  GlucoMoment
//

import SwiftUI

/// 稳糖分圆环：环的长度和颜色表示分数高低，中间是数字。没有分数时显示「—」
struct ScoreRing: View {
    let score: Int?
    var diameter: CGFloat = 44
    /// 大号圆环在数字下方写「稳糖分」
    var showsCaption = false

    private var tint: Color { Color.stableScore(score) }
    private var lineWidth: CGFloat { max(3.5, diameter * 0.095) }
    private var progress: CGFloat { CGFloat(min(max(score ?? 0, 0), 100)) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: diameter * (showsCaption ? 0.3 : 0.36), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(score ?? 0)))
                    .foregroundStyle(score == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                if showsCaption {
                    Text("稳糖分")
                        .font(.system(size: diameter * 0.12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .minimumScaleFactor(0.6)
            .padding(lineWidth)
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth, value: score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("稳糖分")
        .accessibilityValue(score.map { "\($0) 分" } ?? "暂无")
    }
}

#Preview {
    HStack(spacing: 20) {
        ScoreRing(score: 96, diameter: 96, showsCaption: true)
        ScoreRing(score: 78)
        ScoreRing(score: 62)
        ScoreRing(score: 41)
        ScoreRing(score: nil)
    }
    .padding()
}
