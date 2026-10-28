//
//  MetricCard.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

struct MetricCard: View {
    let metric: DashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: metric.systemImage)
                .font(.headline)
                .foregroundStyle(metric.tint)
                .frame(width: 34, height: 34)
                .background(metric.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metric.value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: metric.value)
                Text(metric.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
