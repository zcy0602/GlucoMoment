//
//  PlaneHeightMap.swift
//  GlucoMoment
//

import Foundation
import simd

/// 桌面平面坐标系中的矩形区域（单位：米）。平面坐标系原点在桌面上，y 轴为平面法向。
nonisolated struct PlaneRegion: Sendable, Hashable {
    var minX: Float
    var maxX: Float
    var minZ: Float
    var maxZ: Float

    var width: Float { maxX - minX }
    var depth: Float { maxZ - minZ }

    /// 以某点为中心、指定半边长的正方形区域。
    static func square(center: SIMD2<Float>, halfExtent: Float) -> PlaneRegion {
        PlaneRegion(
            minX: center.x - halfExtent,
            maxX: center.x + halfExtent,
            minZ: center.y - halfExtent,
            maxZ: center.y + halfExtent
        )
    }
}

/// 桌面上方的高度网格。`heights` 按行优先存储，行沿 z 方向、列沿 x 方向；
/// 未观测到的格子为 NaN。
nonisolated struct PlaneHeightMap: Sendable {
    /// 平面坐标到世界坐标的变换（通常来自 ARPlaneAnchor.transform）。
    let planeTransform: simd_float4x4
    let region: PlaneRegion
    let cellSize: Float
    let columns: Int
    let rows: Int
    private(set) var heights: [Float]

    init(planeTransform: simd_float4x4, region: PlaneRegion, cellSize: Float, heights: [Float]) {
        let columns = Self.cellCount(span: region.width, cellSize: cellSize)
        let rows = Self.cellCount(span: region.depth, cellSize: cellSize)
        precondition(heights.count == columns * rows, "高度网格尺寸不匹配")
        self.planeTransform = planeTransform
        self.region = region
        self.cellSize = cellSize
        self.columns = columns
        self.rows = rows
        self.heights = heights
    }

    static func cellCount(span: Float, cellSize: Float) -> Int {
        max(1, Int((span / cellSize).rounded(.up)))
    }

    var cellArea: Float { cellSize * cellSize }
    var cellCount: Int { heights.count }

    func index(column: Int, row: Int) -> Int {
        row * columns + column
    }

    func cellIndex(atPlanePoint point: SIMD2<Float>) -> Int? {
        let column = Int(((point.x - region.minX) / cellSize).rounded(.down))
        let row = Int(((point.y - region.minZ) / cellSize).rounded(.down))
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return index(column: column, row: row)
    }

    /// 格子中心在平面坐标系中的 (x, z)。
    func cellCenter(_ index: Int) -> SIMD2<Float> {
        let column = index % columns
        let row = index / columns
        return SIMD2(
            region.minX + (Float(column) + 0.5) * cellSize,
            region.minZ + (Float(row) + 0.5) * cellSize
        )
    }

    func height(at index: Int) -> Float? {
        let value = heights[index]
        return value.isNaN ? nil : value
    }

    /// 格子中心在指定高度处的世界坐标。
    func worldPoint(cell index: Int, height: Float) -> SIMD3<Float> {
        let center = cellCenter(index)
        let world = planeTransform * SIMD4<Float>(center.x, height, center.y, 1)
        return SIMD3(world.x, world.y, world.z)
    }

    /// 已观测格子占比。
    var observedFraction: Double {
        guard !heights.isEmpty else { return 0 }
        return Double(heights.count { !$0.isNaN }) / Double(heights.count)
    }

    /// 用 3×3 邻域中值填补小空洞（邻域内至少 `minimumNeighbors` 个观测值）。
    func fillingSmallHoles(passes: Int = 2, minimumNeighbors: Int = 4) -> PlaneHeightMap {
        var current = heights
        for _ in 0..<passes {
            var next = current
            var changed = false
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = index(column: column, row: row)
                    guard current[index].isNaN else { continue }

                    var neighbors: [Float] = []
                    neighbors.reserveCapacity(8)
                    for dz in -1...1 {
                        for dx in -1...1 where dx != 0 || dz != 0 {
                            let neighborColumn = column + dx
                            let neighborRow = row + dz
                            guard neighborColumn >= 0, neighborColumn < columns,
                                  neighborRow >= 0, neighborRow < rows else { continue }
                            let value = current[self.index(column: neighborColumn, row: neighborRow)]
                            if !value.isNaN {
                                neighbors.append(value)
                            }
                        }
                    }

                    if neighbors.count >= minimumNeighbors {
                        next[index] = Self.median(of: &neighbors)
                        changed = true
                    }
                }
            }
            current = next
            if !changed { break }
        }

        return PlaneHeightMap(planeTransform: planeTransform, region: region, cellSize: cellSize, heights: current)
    }

    /// ARKit 的平面估计可能有几毫米偏差：取 ±3cm 范围内最密集的 2mm 高度区间作为真实桌面。
    func estimatedTableOffset(searchRange: ClosedRange<Float> = -0.03...0.03, binSize: Float = 0.002) -> Float {
        let binCount = Int(((searchRange.upperBound - searchRange.lowerBound) / binSize).rounded(.up))
        var bins = [Int](repeating: 0, count: binCount)
        for value in heights where !value.isNaN && searchRange.contains(value) {
            let bin = min(binCount - 1, Int((value - searchRange.lowerBound) / binSize))
            bins[bin] += 1
        }
        guard let best = bins.indices.max(by: { bins[$0] < bins[$1] }), bins[best] > 0 else { return 0 }
        return searchRange.lowerBound + (Float(best) + 0.5) * binSize
    }

    /// 所有高度减去偏移量，使桌面回到 0。
    func offsettingHeights(by offset: Float) -> PlaneHeightMap {
        PlaneHeightMap(
            planeTransform: planeTransform,
            region: region,
            cellSize: cellSize,
            heights: heights.map { $0.isNaN ? $0 : $0 - offset }
        )
    }

    static func median(of values: inout [Float]) -> Float {
        values.sort()
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

/// 把多帧 LiDAR 深度融合成一张桌面高度图：每个格子取所有观测高度的中位数，以抑制单帧噪声。
nonisolated struct PlaneHeightMapBuilder: Sendable {
    let planeTransform: simd_float4x4
    let region: PlaneRegion
    let cellSize: Float
    /// 采用的最低置信度（ARConfidenceLevel 原始值）。
    let minimumConfidence: UInt8
    /// 有效高度范围，过滤桌下噪点和手、餐具等明显过高的物体。
    let heightRange: ClosedRange<Float>
    /// LiDAR 有效测距范围（米）。
    let depthRange: ClosedRange<Float>

    private let worldToPlane: simd_float4x4
    private let columns: Int
    private let rows: Int
    private var sampleCells: [Int32] = []
    private var sampleHeights: [Float] = []

    private(set) var keyframeCount = 0

    init(
        planeTransform: simd_float4x4,
        region: PlaneRegion,
        cellSize: Float = 0.002,
        minimumConfidence: UInt8 = 1,
        heightRange: ClosedRange<Float> = -0.03...0.35,
        depthRange: ClosedRange<Float> = 0.1...1.5
    ) {
        self.planeTransform = planeTransform
        self.region = region
        self.cellSize = cellSize
        self.minimumConfidence = minimumConfidence
        self.heightRange = heightRange
        self.depthRange = depthRange
        worldToPlane = planeTransform.inverse
        columns = PlaneHeightMap.cellCount(span: region.width, cellSize: cellSize)
        rows = PlaneHeightMap.cellCount(span: region.depth, cellSize: cellSize)
    }

    var sampleCount: Int { sampleCells.count }

    mutating func add(_ keyframe: DepthKeyframe) {
        keyframeCount += 1
        sampleCells.reserveCapacity(sampleCells.count + keyframe.depth.count)
        sampleHeights.reserveCapacity(sampleHeights.count + keyframe.depth.count)

        for row in 0..<keyframe.height {
            for column in 0..<keyframe.width {
                let pixelIndex = row * keyframe.width + column
                if let confidence = keyframe.confidence, confidence[pixelIndex] < minimumConfidence {
                    continue
                }

                let depth = keyframe.depth[pixelIndex]
                guard depth.isFinite, depthRange.contains(depth) else { continue }

                let world = keyframe.projection.worldPoint(
                    pixel: SIMD2(Float(column) + 0.5, Float(row) + 0.5),
                    depth: depth
                )
                let plane = worldToPlane * SIMD4<Float>(world, 1)
                guard heightRange.contains(plane.y) else { continue }

                let cellColumn = Int(((plane.x - region.minX) / cellSize).rounded(.down))
                let cellRow = Int(((plane.z - region.minZ) / cellSize).rounded(.down))
                guard cellColumn >= 0, cellColumn < columns, cellRow >= 0, cellRow < rows else { continue }

                sampleCells.append(Int32(cellRow * columns + cellColumn))
                sampleHeights.append(plane.y)
            }
        }
    }

    func build() -> PlaneHeightMap {
        let cellCount = columns * rows

        // 计数排序：先统计每格样本数，再把高度按格子分桶，最后逐格求中位数。
        var counts = [Int](repeating: 0, count: cellCount)
        for cell in sampleCells {
            counts[Int(cell)] += 1
        }

        var offsets = [Int](repeating: 0, count: cellCount + 1)
        for index in 0..<cellCount {
            offsets[index + 1] = offsets[index] + counts[index]
        }

        var cursor = offsets
        var bucketed = [Float](repeating: 0, count: sampleHeights.count)
        for (cell, height) in zip(sampleCells, sampleHeights) {
            let position = cursor[Int(cell)]
            bucketed[position] = height
            cursor[Int(cell)] = position + 1
        }

        var heights = [Float](repeating: .nan, count: cellCount)
        var scratch: [Float] = []
        for index in 0..<cellCount where counts[index] > 0 {
            scratch.removeAll(keepingCapacity: true)
            scratch.append(contentsOf: bucketed[offsets[index]..<offsets[index + 1]])
            heights[index] = PlaneHeightMap.median(of: &scratch)
        }

        return PlaneHeightMap(planeTransform: planeTransform, region: region, cellSize: cellSize, heights: heights)
    }
}
