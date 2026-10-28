//
//  NutritionStrip.swift
//  GlucoMoment
//

import SwiftUI

/// 一行四列的营养数值：热量、碳水、蛋白质、脂肪。碳水与血糖关系最大，用饮食色突出
struct NutritionStrip: View {
    let caloriesKcal: Double
    let carbohydratesGrams: Double
    let proteinGrams: Double
    let fatGrams: Double

    var body: some View {
        HStack(spacing: 0) {
            column(title: "热量", value: caloriesKcal, unit: "千卡")
            divider
            column(title: "碳水", value: carbohydratesGrams, unit: "克", tint: .mealTint)
            divider
            column(title: "蛋白质", value: proteinGrams, unit: "克")
            divider
            column(title: "脂肪", value: fatGrams, unit: "克")
        }
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Divider()
            .frame(height: 34)
    }

    private func column(title: String, value: Double, unit: String, tint: Color = .primary) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(DisplayFormat.whole(value))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: value))
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: value)
    }
}

#Preview {
    NutritionStrip(caloriesKcal: 450, carbohydratesGrams: 45, proteinGrams: 40, fatGrams: 18)
        .cardBackground()
        .padding()
        .background(Color(.systemGroupedBackground))
}
