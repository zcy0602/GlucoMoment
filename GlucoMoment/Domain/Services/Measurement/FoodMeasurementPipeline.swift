//
//  FoodMeasurementPipeline.swift
//  GlucoMoment
//

import Foundation
import simd

/// 用户在测量审核页做出的修正。
nonisolated struct FoodMeasurementAdjustments: Sendable, Hashable {
    /// 容器序号 → 用户选择的容器类型。
    var containerTypes: [Int: FoodContainerType] = [:]
    /// 上层食物序号 → 用户指定的层厚（厘米）。
    var layerThicknessCentimeters: [Int: Double] = [:]
}

nonisolated struct FoodMeasurementOutput: Sendable {
    var measurements: [FoodMeasuredItem]
    /// 容器序号 → 推算出的容器几何；无法估计的容器不在其中。
    var containers: [Int: ContainerGeometry]
    /// 实际参与体积计算的区域在照片上的投影，用于叠加显示。
    var overlay: FoodLabelRaster
    var labelCentroids: [Int32: SIMD2<Float>]
}

/// 把高度图、检测结果和分割遮罩组合成每个食物的测量摘要。纯计算，可在后台反复调用（用户每次修正后重算）。
nonisolated enum FoodMeasurementPipeline {
    static func run(
        heightMap: PlaneHeightMap,
        cellImagePoints: [SIMD2<Float>?],
        detection: FoodDetectionResult,
        masks: [Int: FoodMaskRaster],
        adjustments: FoodMeasurementAdjustments,
        overlaySize: (width: Int, height: Int)
    ) -> FoodMeasurementOutput {
        let labels = FoodCellLabeler.label(
            heightMap: heightMap,
            cellImagePoints: cellImagePoints,
            masks: masks,
            items: detection.items
        )

        // 估计容器：在容器框范围内的高度图中寻找碗口。
        var containerGeometries: [Int: ContainerGeometry] = [:]
        for container in detection.containers {
            let type = adjustments.containerTypes[container.index] ?? container.type
            guard type != .noContainer else { continue }
            let cells = FoodCellLabeler.cells(inside: container.box, cellImagePoints: cellImagePoints)
            if let geometry = ContainerRimEstimator.estimate(in: heightMap, cells: cells, type: type) {
                containerGeometries[container.index] = geometry
            }
        }

        let containerOrder = containerGeometries.keys.sorted()
        let containerPositions = Dictionary(uniqueKeysWithValues: containerOrder.enumerated().map { ($1, $0) })
        let geometries = containerOrder.compactMap { containerGeometries[$0] }

        let volumeItems = detection.items.map { item in
            FoodVolumeItem(
                label: Int32(item.index),
                containerIndex: item.containerIndex.flatMap { containerPositions[$0] },
                layering: item.layeredOnIndex.map { under in
                    let range = item.layerThicknessCentimeters ?? 0.5...2.0
                    return FoodLayering(
                        underlyingLabel: Int32(under),
                        thicknessMin: Float(range.lowerBound / 100),
                        thicknessMax: Float(range.upperBound / 100),
                        userThickness: adjustments.layerThicknessCentimeters[item.index].map { Float($0 / 100) }
                    )
                }
            )
        }

        let volumes = FoodVolumeEstimator().estimate(
            heightMap: heightMap,
            cellLabels: labels,
            items: volumeItems,
            containers: geometries
        )

        let measurements = zip(detection.items, volumes).map { item, volume in
            let density = FoodDensityTable.resolve(
                name: item.name,
                category: item.category,
                modelRange: item.densityRange
            )
            let containerType = item.containerIndex.flatMap { containerGeometries[$0]?.type } ?? .noContainer
            return FoodMeasuredItem(
                detection: item,
                measurement: FoodMeasurementBuilder.makeMeasurement(
                    volume: volume,
                    containerType: containerType,
                    density: density
                ),
                layeredOnName: item.layeredOnIndex.flatMap { detection.item(index: $0)?.name }
            )
        }

        var overlay = FoodLabelRaster(width: overlaySize.width, height: overlaySize.height)
        for cell in labels.indices where labels[cell] >= 0 {
            if let point = cellImagePoints[cell] {
                overlay.setLabel(labels[cell], at: point)
            }
        }
        overlay = overlay.dilatingIntoHoles().dilatingIntoHoles()

        return FoodMeasurementOutput(
            measurements: measurements,
            containers: containerGeometries,
            overlay: overlay,
            labelCentroids: overlay.centroids()
        )
    }
}
