//
//  FoodVolumeEstimator.swift
//  GlucoMoment
//

import Foundation
import simd

/// 叠放关系：本食物铺在 `underlyingLabel` 对应的食物之上，层厚区间来自模型提示（单位：米）。
nonisolated struct FoodLayering: Sendable, Hashable {
    var underlyingLabel: Int32
    var thicknessMin: Float
    var thicknessMax: Float
    /// 用户通过滑块指定的层厚；设置后不再按区间计算不确定性。
    var userThickness: Float?

    init(underlyingLabel: Int32, thicknessMin: Float, thicknessMax: Float, userThickness: Float? = nil) {
        self.underlyingLabel = underlyingLabel
        self.thicknessMin = max(0, min(thicknessMin, thicknessMax))
        self.thicknessMax = max(0, max(thicknessMin, thicknessMax))
        self.userThickness = userThickness.map { max(0, $0) }
    }

    var nominalThickness: Float {
        userThickness ?? (thicknessMin + thicknessMax) / 2
    }

    /// 体积偏大情形使用的层厚（上层更厚）。
    var thickThickness: Float { userThickness ?? thicknessMax }
    /// 体积偏小情形使用的层厚（上层更薄）。
    var thinThickness: Float { userThickness ?? thicknessMin }
}

/// 参与体积计算的食物：`label` 与标签网格中的值对应。
nonisolated struct FoodVolumeItem: Sendable, Hashable {
    var label: Int32
    var containerIndex: Int?
    var layering: FoodLayering?
}

nonisolated enum FoodVolumeNote: String, Codable, Sendable, Hashable {
    case lowCoverage
    case layeredOnTop
    case partiallyHidden
    case containerShapeAssumed
    case smallPortion

    var message: String {
        switch self {
        case .lowCoverage:
            "深度数据覆盖不足，部分区域按平均高度补全"
        case .layeredOnTop:
            "叠放在其他食物上，层厚为估计值"
        case .partiallyHidden:
            "部分被其他食物遮挡，被遮挡部分为估计值"
        case .containerShapeAssumed:
            "容器内壁形状为预设，碗底深度为估计值"
        case .smallPortion:
            "份量较小，LiDAR 相对误差较大"
        }
    }
}

nonisolated struct FoodVolumeResult: Sendable, Hashable {
    var label: Int32
    var volumeMilliliters: Double
    var volumeMinMilliliters: Double
    var volumeMaxMilliliters: Double
    /// 包含被上层食物遮住部分的占地面积。
    var footprintAreaSquareCentimeters: Double
    var meanHeightCentimeters: Double
    var coverage: Double
    var notes: [FoodVolumeNote]
}

/// 高度图积分法估算体积：每个格子的体积 = (食物顶面 − 容器内底) × 格子面积。
/// 每个格子先归属于可见的顶层食物，再按叠放提示把超出层厚的部分分给下层食物。
nonisolated struct FoodVolumeEstimator: Sendable {
    /// LiDAR 高度测量误差（米），转换为与占地面积成正比的绝对体积误差。
    var heightNoise: Float = 0.003
    /// 小于该体积（毫升）时提示份量较小。
    var smallPortionThreshold: Double = 50
    /// 覆盖率低于该值时提示数据不足。
    var lowCoverageThreshold: Double = 0.7

    /// - Parameters:
    ///   - heightMap: 高度已相对桌面校正的高度图。
    ///   - cellLabels: 与高度图同尺寸，每个格子的顶层可见食物标签，-1 表示非食物。
    func estimate(
        heightMap: PlaneHeightMap,
        cellLabels: [Int32],
        items: [FoodVolumeItem],
        containers: [ContainerGeometry]
    ) -> [FoodVolumeResult] {
        precondition(cellLabels.count == heightMap.cellCount, "标签网格与高度图尺寸不匹配")

        var indexByLabel: [Int32: Int] = [:]
        for (index, item) in items.enumerated() where indexByLabel[item.label] == nil {
            indexByLabel[item.label] = index
        }

        // 第一遍：统计每个食物的可见格子数和有深度观测的格子数。
        var totalCells = [Int](repeating: 0, count: items.count)
        var observedCells = [Int](repeating: 0, count: items.count)
        for cell in 0..<heightMap.cellCount {
            guard let itemIndex = indexByLabel[cellLabels[cell]] else { continue }
            totalCells[itemIndex] += 1
            if heightMap.height(at: cell) != nil {
                observedCells[itemIndex] += 1
            }
        }

        // 没有观测值的格子按该食物已观测格子的平均高度补全，等价于按比例放大。
        let fillFactors = items.indices.map { index in
            observedCells[index] > 0 ? Double(totalCells[index]) / Double(observedCells[index]) : 0
        }

        var nominal = [Double](repeating: 0, count: items.count)
        var low = [Double](repeating: 0, count: items.count)
        var high = [Double](repeating: 0, count: items.count)
        var coveredCells = [Int](repeating: 0, count: items.count)

        for (index, item) in items.enumerated() {
            if let layering = item.layering,
               let underIndex = indexByLabel[layering.underlyingLabel],
               underIndex != index {
                coveredCells[underIndex] += totalCells[index]
            }
        }

        // 第二遍：积分。
        let cellArea = Double(heightMap.cellArea)
        for cell in 0..<heightMap.cellCount {
            guard let itemIndex = indexByLabel[cellLabels[cell]],
                  let top = heightMap.height(at: cell) else { continue }

            let item = items[itemIndex]
            let center = heightMap.cellCenter(cell)
            let bottom = item.containerIndex
                .flatMap { containers.indices.contains($0) ? containers[$0] : nil }?
                .innerBottomHeight(at: center) ?? 0
            let columnHeight = max(0, top - bottom)
            let weight = cellArea * fillFactors[itemIndex]

            if let layering = item.layering,
               let underIndex = indexByLabel[layering.underlyingLabel],
               underIndex != itemIndex {
                let topNominal = min(layering.nominalThickness, columnHeight)
                let topThick = min(layering.thickThickness, columnHeight)
                let topThin = min(layering.thinThickness, columnHeight)

                nominal[itemIndex] += Double(topNominal) * weight
                high[itemIndex] += Double(topThick) * weight
                low[itemIndex] += Double(topThin) * weight

                // 下层食物在上层薄时分得更多，厚时分得更少。
                nominal[underIndex] += Double(columnHeight - topNominal) * weight
                high[underIndex] += Double(columnHeight - topThin) * weight
                low[underIndex] += Double(columnHeight - topThick) * weight
            } else {
                let volume = Double(columnHeight) * weight
                nominal[itemIndex] += volume
                high[itemIndex] += volume
                low[itemIndex] += volume
            }
        }

        return items.enumerated().map { index, item in
            let footprintCells = totalCells[index] + coveredCells[index]
            let footprintArea = Double(footprintCells) * cellArea
            let coverage = totalCells[index] > 0
                ? Double(observedCells[index]) / Double(totalCells[index])
                : 0

            let container = item.containerIndex.flatMap { containers.indices.contains($0) ? containers[$0] : nil }
            let shapeUncertainty = container?.relativeShapeUncertainty ?? ContainerGeometry.Preset.noContainerUncertainty
            let holeUncertainty = 0.5 * (1 - coverage)
            let relative = (shapeUncertainty * shapeUncertainty + holeUncertainty * holeUncertainty).squareRoot()
            let absolute = footprintArea * Double(heightNoise)

            let nominalVolume = nominal[index]
            let minVolume = min(nominalVolume, max(0, low[index] * (1 - relative) - absolute))
            let maxVolume = max(nominalVolume, high[index] * (1 + relative) + absolute)
            let nominalMilliliters = nominalVolume * 1_000_000

            var notes: [FoodVolumeNote] = []
            if coverage < lowCoverageThreshold {
                notes.append(.lowCoverage)
            }
            if item.layering != nil {
                notes.append(.layeredOnTop)
            }
            if coveredCells[index] > 0 {
                notes.append(.partiallyHidden)
            }
            if let container, [.shallowBowl, .deepBowl, .cup].contains(container.type) {
                notes.append(.containerShapeAssumed)
            }
            if nominalMilliliters < smallPortionThreshold {
                notes.append(.smallPortion)
            }

            return FoodVolumeResult(
                label: item.label,
                volumeMilliliters: nominalMilliliters,
                volumeMinMilliliters: minVolume * 1_000_000,
                volumeMaxMilliliters: maxVolume * 1_000_000,
                footprintAreaSquareCentimeters: footprintArea * 10_000,
                meanHeightCentimeters: footprintArea > 0 ? nominalVolume / footprintArea * 100 : 0,
                coverage: coverage,
                notes: notes
            )
        }
    }
}
