//
//  MealSections.swift
//  GlucoMoment
//

import SwiftUI

// 识别结果页和餐食详情页共用的几个区块。只接收基本数据，不依赖 ViewModel

/// 页面顶部的大照片，多张时左右滑动
struct MealPhotoHeader: View {
    let photos: [Data]
    var height: CGFloat = 280

    var body: some View {
        MealPhotoPager(photos: photos) { data in
            Color.clear
                .overlay { PhotoDataImage(data: data) }
                .clipped()
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel(photos.count > 1 ? "\(photos.count) 张餐食照片" : "餐食照片")
    }
}

/// 稳糖分卡片：左边是分数环，右边一眼看懂分数从哪来——升糖负荷高低，以及指南加减分
struct StableScoreSummaryCard: View {
    let score: Int?
    let breakdown: StableScoreBreakdown?
    /// 公式算不出时，沿用模型给出的血糖影响
    let fallbackImpact: String?
    let onShowDetails: () -> Void

    var body: some View {
        Button(action: onShowDetails) {
            HStack(spacing: 16) {
                ScoreRing(score: score, diameter: 88, showsCaption: true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("升糖负荷")
                            .foregroundStyle(.secondary)
                        Text(impact ?? "—")
                            .fontWeight(.semibold)
                            .foregroundStyle(Self.impactColor(impact))
                    }
                    .font(.subheadline)

                    if let breakdown {
                        Text("整餐 GL \(DisplayFormat.oneDecimal(breakdown.glycemicLoad))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !adjustments(breakdown).isEmpty {
                            ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(adjustments(breakdown), id: \.title) { item in
                                    Text("\(item.title) \(item.value)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.tint)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(item.tint.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    } else {
                        Text("有食物缺少类别，暂用 AI 估算的分数")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .cardBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看稳糖分的计算方法")
    }

    private var impact: String? {
        breakdown?.glucoseImpact ?? fallbackImpact
    }

    private struct Adjustment {
        let title: String
        let value: String
        let tint: Color
    }

    private func adjustments(_ breakdown: StableScoreBreakdown) -> [Adjustment] {
        var items: [Adjustment] = []
        let bonus = Color.stableScore(90)
        if breakdown.vegetableBonus >= 0.5 {
            items.append(Adjustment(title: "蔬菜", value: "+\(DisplayFormat.whole(breakdown.vegetableBonus))", tint: bonus))
        }
        if breakdown.proteinBonus >= 0.5 {
            items.append(Adjustment(title: "蛋白质", value: "+\(DisplayFormat.whole(breakdown.proteinBonus))", tint: bonus))
        }
        if breakdown.wholeGrainBonus >= 0.5 {
            items.append(Adjustment(title: "全谷物", value: "+\(DisplayFormat.whole(breakdown.wholeGrainBonus))", tint: bonus))
        }
        if breakdown.addedSugarPenalty >= 0.5 {
            items.append(Adjustment(title: "添加糖", value: "−\(DisplayFormat.whole(breakdown.addedSugarPenalty))", tint: Color.stableScore(40)))
        }
        return items
    }

    static func impactColor(_ impact: String?) -> Color {
        switch impact {
        case "低": Color.stableScore(90)
        case "中等": Color.brandAmber
        case "较高": Color.stableScore(40)
        default: Color.secondary
        }
    }
}

/// 一样食物：类别色点、名称、份量，右侧是碳水
struct FoodItemRow: View {
    let name: String
    let category: FoodCategory?
    let portionDescription: String
    let estimatedGrams: Double
    let carbohydratesGrams: Double
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(category?.tint ?? Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if isHighlighted {
                        Text("已修正")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.insightTint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.insightTint.opacity(0.12), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                Text(DisplayFormat.whole(carbohydratesGrams))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("克碳水")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(category?.rawValue ?? "未分类")
        let portion = portionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !portion.isEmpty {
            parts.append(portion)
        }
        if estimatedGrams > 0 {
            parts.append("\(DisplayFormat.whole(estimatedGrams)) 克")
        }
        return parts.joined(separator: " · ")
    }
}

/// 稳糖建议：编号列出，底部一行出处，点开是评分依据页
struct MealSuggestionsCard: View {
    let suggestions: [String]
    /// 按规则生成时的指南出处；沿用模型建议时为 nil
    let citation: String?

    var body: some View {
        SummaryCard(title: "稳糖建议", systemImage: "sparkles", tint: .insightTint) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.insightTint)
                            .frame(width: 20, height: 20)
                            .background(Color.insightTint.opacity(0.12), in: Circle())
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                        Text(suggestion)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                NavigationLink {
                    ScoreMethodView()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed")
                        Text(citation ?? "由 AI 给出，仅供参考")
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 页面最底部的一句说明，代替原来每张卡片都写的免责声明
struct MealDisclaimerFooter: View {
    var body: some View {
        Text("营养数值由 AI 根据照片估算，稳糖分和建议仅供饮食记录参考，不能代替医生或营养师的意见。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 4)
    }
}

/// 稳糖分构成的弹层：逐项列出加减分，底部进入评分依据页
struct ScoreBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    let score: Int?
    let breakdown: StableScoreBreakdown?

    private typealias Calculator = StableScoreCalculator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        ScoreRing(score: score, diameter: 120, showsCaption: true)
                        if let breakdown {
                            Text("升糖负荷\(breakdown.glucoseImpact) · GL \(DisplayFormat.oneDecimal(breakdown.glycemicLoad))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                if let breakdown {
                    Section {
                        row("基础分", detail: "由整餐升糖负荷决定", value: DisplayFormat.oneDecimal(breakdown.baseScore))
                        row(
                            "蔬菜",
                            detail: "\(DisplayFormat.whole(breakdown.vegetableGrams)) 克，每餐 \(DisplayFormat.whole(Calculator.vegetableTargetGrams)) 克得满分",
                            value: "+\(DisplayFormat.oneDecimal(breakdown.vegetableBonus))"
                        )
                        row(
                            "蛋白质",
                            detail: "每餐 \(DisplayFormat.whole(Calculator.proteinTargetGrams)) 克得满分",
                            value: "+\(DisplayFormat.oneDecimal(breakdown.proteinBonus))"
                        )
                        row(
                            "全谷物",
                            detail: breakdown.hasStaple ? "占主食 1/3 以上得分" : "这一餐主食很少，不计",
                            value: "+\(DisplayFormat.oneDecimal(breakdown.wholeGrainBonus))"
                        )
                        row(
                            "添加糖",
                            detail: "\(DisplayFormat.whole(breakdown.addedSugarCarbs)) 克，每克扣 \(DisplayFormat.oneDecimal(Calculator.addedSugarPenaltyPerGram)) 分",
                            value: "−\(DisplayFormat.oneDecimal(breakdown.addedSugarPenalty))"
                        )
                        LabeledContent("稳糖分") {
                            Text("\(breakdown.score)")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.stableScore(breakdown.score))
                        }
                    } header: {
                        Text("分数构成")
                    } footer: {
                        Text("升糖负荷（GL）= 类别 GI × 可利用碳水 ÷ 100，整餐相加。GL 越低，基础分越高。")
                    }
                } else {
                    Section {
                        Text("有食物缺少类别，暂时显示 AI 估算的分数。给每样食物选好类别后，会按公式重新计算。")
                            .font(.subheadline)
                    }
                }

                Section {
                    NavigationLink {
                        ScoreMethodView()
                    } label: {
                        Label("评分依据与出处", systemImage: "book.closed")
                    }
                }
            }
            .navigationTitle("稳糖分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, detail: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.body.monospacedDigit())
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
