//
//  FoodScanDemoView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/7/6.
//

import SwiftUI

struct FoodScanDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = FoodScanViewModel()
    @State private var showSavedState = false

    var body: some View {
        DemoScreen(title: viewModel.title) {
            CameraPreviewCard(stateText: viewModel.scanStateText)
            RecognitionSummaryCard(result: viewModel.result)
            NutritionGrid(result: viewModel.result)
            SuggestionListCard(suggestions: viewModel.result.suggestions)

            Button(action: saveDemoRecord) {
                Label(showSavedState ? "已保存" : viewModel.saveButtonTitle, systemImage: showSavedState ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(showSavedState)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }

    private func saveDemoRecord() {
        withAnimation(.snappy) {
            showSavedState = true
        }
    }
}

private struct CameraPreviewCard: View {
    let stateText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("ScanFoodSample2")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        .black.opacity(0.06),
                        .black.opacity(0.18),
                        .black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ScanFrame()
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .padding(15)

                VStack {
                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("鸡胸藜麦沙拉")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(stateText)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "camera.viewfinder")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.28), in: Circle())
                    }
                    .padding(24)
                }
            }
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 38
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private struct RecognitionSummaryCard: View {
    let result: FoodRecognitionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.name)
                        .font(.title3.weight(.semibold))
                    Text("预计 \(result.calories) · 碳水 \(result.carbs)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ScanScoreBadge(score: result.score)
            }

            FlowLayout(spacing: 8) {
                ForEach(result.ingredients, id: \.self) { ingredient in
                    PillTag(title: ingredient, tint: Color.brandTeal)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NutritionGrid: View {
    let result: FoodRecognitionResult

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NutritionMetric(title: "碳水", value: result.carbs, icon: "leaf", tint: Color.brandTeal)
            NutritionMetric(title: "蛋白质", value: result.protein, icon: "bolt.heart", tint: Color.brandLeaf)
            NutritionMetric(title: "脂肪", value: result.fat, icon: "drop", tint: Color.brandAmber)
            NutritionMetric(title: "血糖影响", value: result.glucoseImpact, icon: "waveform.path.ecg", tint: Color.brandRose)
        }
    }
}

private struct NutritionMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

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

private struct SuggestionListCard: View {
    let suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("稳糖建议", systemImage: "sparkles")
                .font(.headline)

            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandLeaf)
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ScanScoreBadge: View {
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
        FoodScanDemoView()
    }
}
