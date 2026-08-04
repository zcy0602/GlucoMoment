//
//  MealReviewDetailView.swift
//  GlucoMoment
//

import SwiftUI
import UIKit

struct MealReviewDetailView: View {
  let meal: MealRecord
  let photoStore: any MealPhotoStoring

  @State private var photoData: Data?

  var body: some View {
    DemoScreen(title: "餐食详情") {
      mealPhoto
      mealHeader
      nutritionGrid

      if let context = meal.userFoodContext, !context.isEmpty {
        DetailTextCard(
          title: "识别前补充",
          icon: "text.bubble",
          text: context,
          tint: Color.brandTeal
        )
      }

      if let note = meal.note, !note.isEmpty {
        DetailTextCard(
          title: "我的备注",
          icon: "note.text",
          text: note,
          tint: Color.brandAmber
        )
      }

      SectionHeader("食物与营养")
      VStack(spacing: 12) {
        ForEach(meal.items) { item in
          MealFoodItemDetailCard(item: item)
        }
      }

      if !meal.suggestions.isEmpty {
        MealDetailListCard(
          title: "稳糖建议",
          icon: "sparkles",
          rows: meal.suggestions,
          rowIcon: "checkmark.circle.fill",
          tint: Color.brandLeaf
        )
      }

      let confirmations = meal.uncertainties + meal.followUpQuestions
      if !confirmations.isEmpty {
        MealDetailListCard(
          title: "识别时需要确认",
          icon: "questionmark.bubble",
          rows: confirmations,
          rowIcon: "questionmark.circle",
          tint: Color.brandAmber
        )
      }

      analysisMetadata
    }
    .accessibilityIdentifier("meal-review-detail")
    .task(id: meal.photoFilename) {
      guard let filename = meal.photoFilename else {
        photoData = nil
        return
      }
      photoData = await photoStore.jpegData(filename: filename)
    }
  }

  @ViewBuilder
  private var mealPhoto: some View {
    if let photoData, let image = UIImage(data: photoData) {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .bottomLeading) {
          LinearGradient(
            colors: [.clear, .black.opacity(0.72)],
            startPoint: .center,
            endPoint: .bottom
          )
          .clipShape(RoundedRectangle(cornerRadius: 22))
          .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
              Text(meal.title)
                .font(.headline)
              if let confidence = meal.analysisConfidence {
                Text(
                  "Review 后已保存 · 识别置信度 \(confidence.formatted(.percent.precision(.fractionLength(0))))"
                )
                .font(.caption)
              }
            }
            .foregroundStyle(.white)
            .padding(16)
          }
        }
        .accessibilityLabel("已保存的餐食照片")
    }
  }

  private var mealHeader: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text(meal.title)
            .font(.title3.weight(.semibold))
          Text(meal.eatenAt.formatted(date: .abbreviated, time: .shortened))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()

        VStack(spacing: 2) {
          Text(meal.caloriesKcal.formatted(.number.precision(.fractionLength(0))))
            .font(.title3.weight(.bold))
          Text("千卡")
            .font(.caption2)
        }
        .foregroundStyle(Color.brandLeaf)
        .frame(width: 64, height: 56)
        .background(Color.brandLeaf.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
      }

      FlowLayout(spacing: 8) {
        PillTag(title: meal.mealPeriod.rawValue, tint: Color.brandTeal)
        PillTag(
          title: meal.source == .aiPhoto ? "AI 图片识别" : "手动记录",
          tint: Color.brandLeaf
        )
        if let score = meal.score {
          PillTag(title: "稳糖分 \(score)", tint: Color.brandLeaf)
        }
      }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
  }

  private var nutritionGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      MealNutritionMetric(
        title: "碳水", value: grams(meal.carbohydratesGrams), icon: "leaf", tint: Color.brandTeal)
      MealNutritionMetric(
        title: "蛋白质", value: grams(meal.proteinGrams), icon: "bolt.heart", tint: Color.brandLeaf)
      MealNutritionMetric(
        title: "脂肪", value: grams(meal.fatGrams), icon: "drop", tint: Color.brandAmber)
      MealNutritionMetric(
        title: "膳食纤维", value: grams(meal.fiberGrams), icon: "laurel.leading", tint: Color.brandLeaf)
      if let glucoseImpact = meal.glucoseImpact {
        MealNutritionMetric(
          title: "血糖影响",
          value: glucoseImpact,
          icon: "waveform.path.ecg",
          tint: Color.brandRose
        )
      }
    }
  }

  private var analysisMetadata: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("识别记录", systemImage: "info.circle")
        .font(.headline)

      if let provider = meal.aiProvider {
        LabeledContent("服务", value: provider)
      }
      if let model = meal.aiModel {
        LabeledContent("模型", value: model)
      }
      if let promptVersion = meal.promptVersion {
        LabeledContent("提示词版本", value: promptVersion)
      }

      Text("这是保存时的 Review 快照，不会在查看详情时重新上传或重新识别照片。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .font(.subheadline)
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
  }

  private func grams(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0))))g"
  }
}

private struct MealFoodItemDetailCard: View {
  let item: MealFoodItem

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.name)
            .font(.headline)
          Text(item.portionDescription)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(item.caloriesKcal.formatted(.number.precision(.fractionLength(0)))) 千卡")
          .font(.subheadline.weight(.semibold))
      }

      HStack(spacing: 8) {
        MiniNutrient(
          title: "重量",
          value: "\(item.estimatedGrams.formatted(.number.precision(.fractionLength(0))))g")
        MiniNutrient(
          title: "碳水",
          value: "\(item.carbohydratesGrams.formatted(.number.precision(.fractionLength(0))))g")
        MiniNutrient(
          title: "蛋白质",
          value: "\(item.proteinGrams.formatted(.number.precision(.fractionLength(0))))g")
        MiniNutrient(
          title: "脂肪", value: "\(item.fatGrams.formatted(.number.precision(.fractionLength(0))))g")
      }

      if let evidence = item.evidence, !evidence.isEmpty {
        Label(evidence, systemImage: "eye")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      ForEach(item.uncertainties, id: \.self) { uncertainty in
        Label(uncertainty, systemImage: "exclamationmark.circle")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
  }
}

private struct MiniNutrient: View {
  let title: String
  let value: String

  var body: some View {
    VStack(spacing: 3) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.weight(.semibold))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct MealNutritionMetric: View {
  let title: String
  let value: String
  let icon: String
  let tint: Color

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(tint)
        .frame(width: 32, height: 32)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.headline)
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }
}

private struct DetailTextCard: View {
  let title: String
  let icon: String
  let text: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon)
        .font(.headline)
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
  }
}

private struct MealDetailListCard: View {
  let title: String
  let icon: String
  let rows: [String]
  let rowIcon: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: icon)
        .font(.headline)
      ForEach(rows, id: \.self) { row in
        Label(row, systemImage: rowIcon)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
  }
}

#Preview {
  let dependencies = AppDependencies.preview()
  NavigationStack {
    MealReviewDetailView(
    
      meal: MealRecord(
        eatenAt: .now,
        mealPeriod: .lunch,
        title: "鸡胸肉蔬菜沙拉",
        source: .aiPhoto,
        userFoodContext: "鸡胸肉约一掌大小，无额外酱汁",
        note: "实际吃完",
        caloriesKcal: 352,
        carbohydratesGrams: 16,
        proteinGrams: 42,
        fatGrams: 12,
        fiberGrams: 6,
        aiProvider: "qwen-direct",
        aiModel: "qwen3.7-plus",
        promptVersion: "food-analysis-v1",
        analysisConfidence: 0.75,
        glucoseImpact: "低",
        score: 85,
        suggestions: ["确认烹饪用油后估算会更准确。"],
        followUpQuestions: ["蔬菜是否额外刷油？"],
        uncertainties: ["芝士具体种类无法确认。"],
        items: [
          MealFoodItem(
            name: "烤鸡胸肉",
            portionDescription: "约一掌大小",
            estimatedGrams: 130,
            caloriesKcal: 220,
            carbohydratesGrams: 0,
            proteinGrams: 39,
            fatGrams: 6,
            fiberGrams: 0,
            confidence: 0.82,
            evidence: "图片可见烤痕和鸡肉纹理",
            uncertainties: ["烹饪用油量未知"]
          )
        ]
      ),
      photoStore: dependencies.mealPhotoStore
    )
  }
}
