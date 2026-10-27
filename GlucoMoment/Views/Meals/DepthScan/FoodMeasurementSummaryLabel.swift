//
//  FoodMeasurementSummaryLabel.swift
//  GlucoMoment
//

import SwiftUI

/// 一行展示 LiDAR 实测结果：体积、容器与实测克重区间。
struct FoodMeasurementSummaryLabel: View {
    let measurement: FoodItemMeasurement

    var body: some View {
        Label {
            Text(summary)
        } icon: {
            Image(systemName: "cube.transparent")
        }
        .font(.footnote)
        .foregroundStyle(Color.brandTeal)
        .accessibilityLabel("LiDAR 实测，\(summary)")
    }

    private var summary: String {
        let volume = measurement.volumeMilliliters.formatted(.number.precision(.fractionLength(0)))
        let lower = measurement.measuredGramsMin.formatted(.number.precision(.fractionLength(0)))
        let upper = measurement.measuredGramsMax.formatted(.number.precision(.fractionLength(0)))
        var parts = ["\(measurement.method.label) 约 \(volume) ml"]
        if measurement.containerType != .noContainer {
            parts.append(measurement.containerType.label)
        }
        parts.append("实测 \(lower)～\(upper)g")
        return parts.joined(separator: " · ")
    }
}
