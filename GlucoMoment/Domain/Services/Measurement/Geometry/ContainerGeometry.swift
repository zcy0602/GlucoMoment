//
//  ContainerGeometry.swift
//  GlucoMoment
//

import Foundation
import simd

/// 容器的几何模型。LiDAR 看不到被食物遮住的碗底，因此用「实测碗口 + 预设内壁形状」推算内底高度。
/// 所有长度单位为米，坐标为桌面平面坐标系 (x, z)，高度相对桌面。
nonisolated struct ContainerGeometry: Sendable, Hashable {
    /// 各类容器的经验参数，集中定义便于后续用实测数据校准。
    enum Preset {
        /// 平盘盘心厚度。
        static let plateBaseThickness: Float = 0.006
        /// 碗底圈足 + 碗底厚度。
        static let bowlBaseThickness: Float = 0.008
        /// 杯底厚度。
        static let cupBaseThickness: Float = 0.010
        /// 碗壁 / 杯壁厚度。
        static let wallThickness: Float = 0.004
        /// 无法测得碗口高度时，内部深度与碗口直径之比。
        static let shallowBowlDepthRatio: Float = 0.22
        static let deepBowlDepthRatio: Float = 0.42
        static let cupDepthRatio: Float = 1.1
        /// 碗内壁轮廓指数：浅碗接近抛物面，深碗底部更平、碗壁更陡。
        static let shallowBowlProfileExponent: Float = 2
        static let deepBowlProfileExponent: Float = 4
        /// 无容器（直接放在桌面上）时的相对体积误差。
        static let noContainerUncertainty: Double = 0.05
    }

    let type: FoodContainerType
    /// 碗口圆心（平面坐标 x, z）。
    let center: SIMD2<Float>
    /// 碗口外半径。
    let rimRadius: Float
    /// 碗口距桌面的高度（实测可信时取实测值，否则为预设推算值）。
    let rimHeight: Float
    /// 原始实测碗口高度，切换容器类型时重新参与判断。
    let measuredRimHeight: Float?

    /// - Parameter measuredRimHeight: 实测碗口高度；为 nil 或不可信时按预设深径比推算。
    init(type: FoodContainerType, center: SIMD2<Float>, rimRadius: Float, measuredRimHeight: Float?) {
        self.type = type
        self.center = center
        self.rimRadius = max(rimRadius, 0)
        self.measuredRimHeight = measuredRimHeight

        let diameter = 2 * max(rimRadius - Preset.wallThickness, 0)
        let presetHeight: Float = switch type {
        case .flatPlate:
            Preset.plateBaseThickness
        case .shallowBowl:
            Preset.bowlBaseThickness + Preset.shallowBowlDepthRatio * diameter
        case .deepBowl:
            Preset.bowlBaseThickness + Preset.deepBowlDepthRatio * diameter
        case .cup:
            Preset.cupBaseThickness + Preset.cupDepthRatio * diameter
        case .noContainer:
            0
        }

        if let measuredRimHeight, measuredRimHeight > Self.baseThickness(for: type) + 0.003 {
            rimHeight = measuredRimHeight
        } else {
            rimHeight = presetHeight
        }
    }

    static func baseThickness(for type: FoodContainerType) -> Float {
        switch type {
        case .flatPlate:
            Preset.plateBaseThickness
        case .shallowBowl, .deepBowl:
            Preset.bowlBaseThickness
        case .cup:
            Preset.cupBaseThickness
        case .noContainer:
            0
        }
    }

    var innerRadius: Float {
        max(rimRadius - Preset.wallThickness, 0)
    }

    /// 碗口以下的内部深度。
    var interiorDepth: Float {
        max(rimHeight - Self.baseThickness(for: type), 0)
    }

    func contains(_ point: SIMD2<Float>) -> Bool {
        guard type != .noContainer else { return false }
        return simd_distance(point, center) <= rimRadius
    }

    /// 某点处的容器内底高度；点不在容器内时返回 nil（此时以桌面为底）。
    func innerBottomHeight(at point: SIMD2<Float>) -> Float? {
        guard contains(point) else { return nil }

        let base = Self.baseThickness(for: type)
        switch type {
        case .flatPlate:
            return min(base, rimHeight)
        case .cup:
            return base
        case .shallowBowl, .deepBowl:
            let radius = innerRadius
            let depth = interiorDepth
            guard radius > 0, depth > 0 else { return base }
            let distance = min(simd_distance(point, center), radius)

            // 幂函数内壁：内底高度 = 底厚 + d·(r/a)^p。p 越大碗底越平、碗壁越陡；
            // 装满时体积为 πa²d·p/(p+2)，浅碗（p=2）为圆柱的 1/2，深碗（p=4）为 2/3。
            let exponent = type == .deepBowl ? Preset.deepBowlProfileExponent : Preset.shallowBowlProfileExponent
            return base + depth * pow(distance / radius, exponent)
        case .noContainer:
            return nil
        }
    }

    /// 形状假设带来的相对体积误差，用于扩大估算区间。
    var relativeShapeUncertainty: Double {
        switch type {
        case .flatPlate:
            0.05
        case .shallowBowl:
            0.12
        case .deepBowl:
            0.15
        case .cup:
            0.08
        case .noContainer:
            Preset.noContainerUncertainty
        }
    }

    func with(type newType: FoodContainerType) -> ContainerGeometry {
        ContainerGeometry(type: newType, center: center, rimRadius: rimRadius, measuredRimHeight: measuredRimHeight)
    }
}

/// 从高度图中估计容器碗口：圆心取凸起区域质心，半径取距离的高分位数，碗口高度取外环高度的高分位数。
nonisolated enum ContainerRimEstimator {
    /// - Parameters:
    ///   - cells: 属于该容器（例如容器检测框投影范围内）的格子索引。
    ///   - minimumHeight: 高于该值的格子视为容器或食物的一部分。
    static func estimate(
        in heightMap: PlaneHeightMap,
        cells: [Int],
        type: FoodContainerType,
        minimumHeight: Float = 0.004
    ) -> ContainerGeometry? {
        let occupied = cells.compactMap { index -> (SIMD2<Float>, Float)? in
            guard let height = heightMap.height(at: index), height > minimumHeight else { return nil }
            return (heightMap.cellCenter(index), height)
        }
        guard occupied.count >= 20 else { return nil }

        let sum = occupied.reduce(SIMD2<Float>.zero) { $0 + $1.0 }
        let center = sum / Float(occupied.count)

        var distances = occupied.map { simd_distance($0.0, center) }
        distances.sort()
        let radius = percentile(distances, 0.97) + heightMap.cellSize / 2
        guard radius > 0.01 else { return nil }

        // 碗口外环：0.85R～R 之间的格子高度的高分位数。
        var rimHeights = occupied.compactMap { cell -> Float? in
            let distance = simd_distance(cell.0, center)
            return distance >= radius * 0.85 ? cell.1 : nil
        }
        rimHeights.sort()
        let rimHeight = rimHeights.isEmpty ? nil : percentile(rimHeights, 0.8)

        return ContainerGeometry(type: type, center: center, rimRadius: radius, measuredRimHeight: rimHeight)
    }

    /// 对已排序数组取分位数（线性插值）。
    static func percentile(_ sorted: [Float], _ fraction: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let position = fraction * Float(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Float(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
