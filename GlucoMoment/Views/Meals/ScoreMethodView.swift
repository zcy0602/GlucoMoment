//
//  ScoreMethodView.swift
//  GlucoMoment
//

import Charts
import SwiftUI

/// 评分依据：三步说清稳糖分怎么算，基础分曲线用图表示。数值直接读取 `StableScoreCalculator`
struct ScoreMethodView: View {
    private typealias Calculator = StableScoreCalculator

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("AI 只负责认出吃了什么、各多少；分数由 App 按固定公式计算，同样的饭菜总是得到同样的分数。")
                        .font(.subheadline)
                    HStack(alignment: .top, spacing: 0) {
                        step(1, icon: "camera.viewfinder", title: "认出食物", tint: .mealTint)
                        arrow
                        step(2, icon: "chart.line.uptrend.xyaxis", title: "算升糖负荷", tint: .glucoseTint)
                        arrow
                        step(3, icon: "checklist", title: "按指南加减", tint: .insightTint)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                baseCurveChart
                    .frame(height: 180)
                    .padding(.vertical, 8)
            } header: {
                Text("基础分：升糖负荷越低越高")
            } footer: {
                Text("升糖负荷（GL）= 类别 GI × 可利用碳水 ÷ 100，整餐相加。GL 10、20 是 WS/T 652—2019 的低、中、高分界。")
            }

            Section {
                ruleRow(icon: "leaf.fill", tint: .mealTint, title: "蔬菜", rule: "每餐 \(DisplayFormat.whole(Calculator.vegetableTargetGrams)) 克得满分", value: "+\(DisplayFormat.whole(Calculator.maximumBonus))")
                ruleRow(icon: "fish.fill", tint: FoodCategory.protein.tint, title: "蛋白质", rule: "每餐 \(DisplayFormat.whole(Calculator.proteinTargetGrams)) 克得满分", value: "+\(DisplayFormat.whole(Calculator.maximumBonus))")
                ruleRow(icon: "circle.grid.3x3.fill", tint: FoodCategory.wholeGrainLegume.tint, title: "全谷物", rule: "占主食的 1/3 以上", value: "+\(DisplayFormat.whole(Calculator.maximumBonus))")
                ruleRow(icon: "cube.fill", tint: FoodCategory.addedSugar.tint, title: "添加糖", rule: "每克扣 \(DisplayFormat.oneDecimal(Calculator.addedSugarPenaltyPerGram)) 分", value: "−\(DisplayFormat.whole(Calculator.maximumAddedSugarPenalty))")
            } header: {
                Text("加减分：来自膳食指南")
            } footer: {
                Text("依据《成人糖尿病食养指南（2023 年版）》与 WS/T 429—2013。总分限制在 \(Calculator.minimumScore)～100 分。")
            }

            Section {
                ForEach(FoodCategory.allCases, id: \.self) { category in
                    LabeledContent {
                        Text(DisplayFormat.whole(category.representativeGI))
                            .monospacedDigit()
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(category.tint)
                                .frame(width: 10, height: 10)
                            Text(category.rawValue)
                        }
                    }
                }
            } header: {
                Text("各类食物的 GI 代表值")
            } footer: {
                Text("主要依据 WS/T 429—2013 附录 A（数据源自《中国食物成分表 2002》），每类取常见食物的代表值。")
            }

            Section {
                DisclosureGroup("\(DietGuideline.allCases.count) 条指南要点") {
                    ForEach(DietGuideline.allCases, id: \.self) { guideline in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(guideline.title) · \(guideline.principleText)")
                                .font(.subheadline.weight(.semibold))
                            Text(guideline.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("建议从哪里来")
            } footer: {
                Text("每条稳糖建议都按固定规则生成，并对应上面的一条指南，不涉及诊断和用药。")
            }

            Section {
                Text("稳糖分帮助你记录和比较饮食，不是医学诊断。同样的食物在不同人身上的血糖反应差别很大，建议结合自己的血糖记录来看；调整饮食或用药请咨询医生或营养师。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("公式版本 \(Calculator.formulaVersion)")
            }
        }
        .navigationTitle("评分依据")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
            .padding(.top, 16)
    }

    private func step(_ number: Int, icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(number) 步：\(title)")
    }

    private func ruleRow(icon: String, tint: Color, title: String, rule: String, value: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: icon, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(rule)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("最多 \(value)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// GL → 基础分的分段折线，标出 10、20 两条分界
    private var baseCurveChart: some View {
        Chart {
            ForEach(Array(Calculator.baseCurve.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("GL", point.glycemicLoad), y: .value("基础分", point.score))
                    .foregroundStyle(Color.glucoseTint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("GL", point.glycemicLoad), y: .value("基础分", point.score))
                    .foregroundStyle(Color.stableScore(Int(point.score)))
                    .annotation(position: .top, spacing: 4) {
                        Text(DisplayFormat.whole(point.score))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            RuleMark(x: .value("低", 10.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary.opacity(0.5))
            RuleMark(x: .value("高", 20.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .chartYScale(domain: 0...100)
        .chartXAxisLabel("整餐 GL")
        .chartYAxis {
            AxisMarks(values: [0, 50, 100])
        }
        .accessibilityLabel("基础分曲线：GL 10 得 85 分，GL 20 得 70 分，GL 越高分数越低")
    }
}

#Preview {
    NavigationStack {
        ScoreMethodView()
    }
}
