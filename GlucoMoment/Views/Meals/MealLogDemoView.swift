//
//  MealLogDemoView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

struct MealLogDemoView: View {
    @State private var viewModel = MealLogViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        DemoScreen(title: viewModel.title) {
            Picker("餐次", selection: $viewModel.selectedMeal) {
                ForEach(viewModel.mealOptions) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            MealSuggestionCard(
                title: viewModel.suggestionTitle,
                text: viewModel.suggestionText,
                tags: viewModel.suggestionTags
            )
            
            NavigationLink {
                FoodScanDemoView()
            } label: {
                Label("拍照识别饮食", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.brandMint)
            .controlSize(.large)
            
            SectionHeader("今日餐食")
            VStack(spacing: 12) {
                ForEach(viewModel.meals) { meal in
                    MealEntryCard(meal: meal)
                }
            }

            
        }
    }
}

private struct MealSuggestionCard: View {
    let title: String
    let text: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                PillTag(title: "可执行", tint: Color.brandTeal)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    PillTag(title: tag, tint: Color.brandLeaf)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MealEntryCard: View {
    let meal: MealEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(meal.title)
                        .font(.headline)
                    Text("\(meal.time) · \(meal.carbs)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ScoreBadge(score: meal.score)
            }

            Text(meal.note)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(meal.tags, id: \.self) { tag in
                    PillTag(title: tag, tint: Color.brandTeal)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ScoreBadge: View {
    let score: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.title3.weight(.bold))
            Text("稳糖分")
                .font(.caption2)
        }
        .foregroundStyle(Color.brandLeaf)
        .frame(width: 62, height: 54)
        .background(Color.brandLeaf.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        MealLogDemoView()
    }
}
