//
//  TodayDashboardView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

struct TodayDashboardView: View {
    @State private var viewModel = TodayDashboardViewModel()

    var body: some View {
        DemoScreen(title: viewModel.title) {
            CurrentGlucoseCard(snapshot: viewModel.currentSnapshot, readings: Array(viewModel.compactReadings))
            MetricsGrid(metrics: viewModel.metrics)
            NextActionCard(text: viewModel.nextAction)

            SectionHeader("今日节奏", subtitle: viewModel.timelineSubtitle)
            VStack(spacing: 10) {
                ForEach(viewModel.timelineEvents) { event in
                    TimelineRow(event: event)
                }
            }
        }
    }
}

private struct CurrentGlucoseCard: View {
    let snapshot: CurrentGlucoseSnapshot
    let readings: [GlucoseReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前估算")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(snapshot.value)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                        Text(snapshot.unit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    PillTag(title: snapshot.stateLabel, tint: snapshot.stateTint)
                }

                Spacer()

                Image(systemName: "heart.text.square")
                    .font(.title)
                    .foregroundStyle(Color.brandTeal)
                    .frame(width: 48, height: 48)
                    .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 16))
            }

            ReadingSparkBars(readings: readings)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.white, Color.brandMint.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

private struct ReadingSparkBars: View {
    let readings: [GlucoseReading]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(readings) { reading in
                Capsule()
                    .fill(reading.state.tint)
                    .frame(width: 8, height: CGFloat(max(28, reading.value - 70)))
                    .frame(maxWidth: .infinity, maxHeight: 92, alignment: .bottom)
                    .accessibilityLabel("\(reading.hour) \(reading.value) mg/dL")
            }
        }
    }
}

private struct MetricsGrid: View {
    let metrics: [DashboardMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(metrics) { metric in
                MetricCard(metric: metric)
            }
        }
    }
}

private struct NextActionCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.brandTeal, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text("下一步建议")
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TimelineRow: View {
    let event: TimelineEvent

    var body: some View {
        HStack(spacing: 14) {
            Text(event.time)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Circle()
                .fill(event.state.tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        TodayDashboardView()
    }
}
