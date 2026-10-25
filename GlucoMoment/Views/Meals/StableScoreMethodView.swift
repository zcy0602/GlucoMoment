//
//  StableScoreMethodView.swift
//  GlucoMoment
//

import SwiftUI

/// 评分依据：说明稳糖分的计算方法和出处。数值直接读取 `StableScoreCalculator`，与实际计算保持一致。
struct StableScoreMethodView: View {
    private typealias Calculator = StableScoreCalculator

    var body: some View {
        List {
            Section {
                Text("AI 只负责识别每样食物是什么、属于哪一类、大约多少克以及营养数值；稳糖分由 App 按下面的公式计算。同样的食物和份量，得到的分数总是一样，修改份量后分数会随之变化。")
            } header: {
                Text("思路")
            } footer: {
                Text("《成人糖尿病食养指南（2023 年版）》指出：碳水化合物的种类和数量，是影响餐后血糖最重要的营养因素。")
            }

            Section("计算步骤") {
                StepRow(number: 1, title: "每样食物的血糖负荷（GL）", detail: "GL = 类别 GI × 可利用碳水 ÷ 100，可利用碳水 = 总碳水 − 膳食纤维。整餐 GL 为各样食物之和。")
                StepRow(number: 2, title: "按整餐 GL 定基础分", detail: baseCurveText)
                StepRow(number: 3, title: "按膳食指南加减分", detail: "蔬菜、蛋白质、全谷物各最多加 \(Self.number(Calculator.maximumBonus)) 分，添加糖最多扣 \(Self.number(Calculator.maximumAddedSugarPenalty)) 分。")
                StepRow(number: 4, title: "合计", detail: "总分限制在 \(Calculator.minimumScore)～100 分之间。")
            }

            Section {
                ForEach(FoodCategory.allCases, id: \.self) { category in
                    LabeledContent(category.rawValue, value: Self.number(category.representativeGI))
                }
            } header: {
                Text("各类食物的 GI 代表值")
            } footer: {
                Text("主要依据 WS/T 429—2013《成人糖尿病患者膳食指导》附录 A（数据源自《中国食物成分表 2002》），每类取常见食物的代表值。同一类食物之间差别可能较大，例如面条、糙米。")
            }

            Section("加减分规则") {
                RuleRow(title: "蔬菜", rule: "每餐 \(Self.number(Calculator.vegetableTargetGrams)) 克得满分，不足按比例", source: "食养指南：餐餐都应有蔬菜，每天应达 500 克")
                RuleRow(title: "蛋白质", rule: "每餐 \(Self.number(Calculator.proteinTargetGrams)) 克得满分，不足按比例", source: "食养指南：蛋白质供能比 15%～20%")
                RuleRow(title: "全谷物", rule: "全谷物和杂豆占主食的 1/3 以上", source: "食养指南：全谷物和杂豆类等低 GI 食物，应占主食的 1/3 以上")
                RuleRow(title: "添加糖", rule: "每克扣 \(Self.number(Calculator.addedSugarPenaltyPerGram)) 分", source: "WS/T 429—2013：限制精制糖摄入")
            }

            Section {
                LabeledContent("低", value: "GL < 10")
                LabeledContent("中等", value: "10 ≤ GL ≤ 20")
                LabeledContent("较高", value: "GL > 20")
            } header: {
                Text("血糖影响分级")
            } footer: {
                Text("依据 WS/T 652—2019《食物血糖生成指数测定方法》第 7.2 条。标准针对 100 克或一份食物，这里把整餐当作一份来分级。")
            }

            Section {
                Text("稳糖分是帮助你记录和比较饮食的参考，不是医学诊断。同一种食物在不同人身上的血糖反应差别很大，建议结合自己的血糖记录来看。如需调整饮食或用药，请咨询医生或营养师。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("说明")
            } footer: {
                Text("公式版本：\(Calculator.formulaVersion)")
            }
        }
        .navigationTitle("评分依据")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var baseCurveText: String {
        let points = Calculator.baseCurve
            .map { "GL \(Self.number($0.glycemicLoad)) → \(Self.number($0.score)) 分" }
            .joined(separator: "，")
        return "\(points)，中间按比例折算。GL 越高，基础分越低。"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.brandLeaf)
                .frame(width: 24, height: 24)
                .background(Color.brandLeaf.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RuleRow: View {
    let title: String
    let rule: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(rule)
                .font(.footnote)
            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        StableScoreMethodView()
    }
}
