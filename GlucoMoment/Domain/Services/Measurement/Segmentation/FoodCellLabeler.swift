//
//  FoodCellLabeler.swift
//  GlucoMoment
//

import Foundation
import simd

/// 把图像遮罩映射到高度图格子，并处理多个遮罩重叠的情况：
/// 1. 叠放关系中的上层食物优先（例如浇头盖在米饭上）；
/// 2. 并排食物的检测框重叠时，从无歧义格子出发做区域生长，遇到高度跳变（深度断层）即停止；
/// 3. 仍无法确定的格子归给「相对位置更靠近框中心」的食物。
nonisolated enum FoodCellLabeler {
    /// 相邻格子高度差超过该值视为深度断层（米）。
    static let depthDiscontinuity: Float = 0.006
    static let maskThreshold: Float = 0.5

    static func label(
        heightMap: PlaneHeightMap,
        cellImagePoints: [SIMD2<Float>?],
        masks: [Int: FoodMaskRaster],
        items: [FoodDetectedItem]
    ) -> [Int32] {
        precondition(cellImagePoints.count == heightMap.cellCount, "格子投影数量与高度图不匹配")

        let itemsByIndex = Dictionary(items.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let orderedIndices = items.map(\.index).filter { masks[$0] != nil }
        var labels = [Int32](repeating: -1, count: heightMap.cellCount)
        var candidates = [[Int]](repeating: [], count: heightMap.cellCount)
        var ambiguous: [Int] = []

        for cell in 0..<heightMap.cellCount {
            guard let point = cellImagePoints[cell] else { continue }
            var hits = orderedIndices.filter { masks[$0]?.value(at: point) ?? 0 > maskThreshold }
            guard !hits.isEmpty else { continue }

            // 去掉被同一格子中其他食物覆盖的下层食物。
            if hits.count > 1 {
                let covered = Set(hits.compactMap { itemsByIndex[$0]?.layeredOnIndex })
                let visible = hits.filter { !covered.contains($0) }
                if !visible.isEmpty {
                    hits = visible
                }
            }

            if hits.count == 1 {
                labels[cell] = Int32(hits[0])
            } else {
                candidates[cell] = hits
                ambiguous.append(cell)
            }
        }

        guard !ambiguous.isEmpty else { return labels }

        // 多源广度优先生长：只穿过高度连续的相邻格子。
        var queue: [Int] = []
        queue.reserveCapacity(heightMap.cellCount)
        for cell in 0..<heightMap.cellCount where labels[cell] >= 0 {
            queue.append(cell)
        }

        var head = 0
        while head < queue.count {
            let cell = queue[head]
            head += 1
            let label = labels[cell]
            let column = cell % heightMap.columns
            let row = cell / heightMap.columns

            for (dx, dz) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let neighborColumn = column + dx
                let neighborRow = row + dz
                guard neighborColumn >= 0, neighborColumn < heightMap.columns,
                      neighborRow >= 0, neighborRow < heightMap.rows else { continue }
                let neighbor = heightMap.index(column: neighborColumn, row: neighborRow)
                guard labels[neighbor] < 0,
                      candidates[neighbor].contains(Int(label)),
                      isContinuous(heightMap.height(at: cell), heightMap.height(at: neighbor)) else { continue }

                labels[neighbor] = label
                queue.append(neighbor)
            }
        }

        // 生长不到的格子按相对框中心距离归属。
        for cell in ambiguous where labels[cell] < 0 {
            guard let point = cellImagePoints[cell] else { continue }
            let best = candidates[cell].min { first, second in
                normalizedDistance(point, box: itemsByIndex[first]?.box)
                    < normalizedDistance(point, box: itemsByIndex[second]?.box)
            }
            if let best {
                labels[cell] = Int32(best)
            }
        }

        return labels
    }

    /// 格子中心是否落在检测框内（可外扩），用于收集容器范围内的格子。
    static func cells(
        inside box: FoodBoundingBox,
        padding: Double = 0.02,
        cellImagePoints: [SIMD2<Float>?]
    ) -> [Int] {
        cellImagePoints.indices.filter { cell in
            guard let point = cellImagePoints[cell] else { return false }
            let x = Double(point.x)
            let y = Double(point.y)
            return x >= box.minX - padding && x <= box.maxX + padding
                && y >= box.minY - padding && y <= box.maxY + padding
        }
    }

    private static func isContinuous(_ first: Float?, _ second: Float?) -> Bool {
        guard let first, let second else { return true }
        return abs(first - second) <= depthDiscontinuity
    }

    /// 0 表示在框中心，1 表示在框边缘。
    private static func normalizedDistance(_ point: SIMD2<Float>, box: FoodBoundingBox?) -> Double {
        guard let box, box.width > 0, box.height > 0 else { return .greatestFiniteMagnitude }
        let dx = abs(Double(point.x) - box.centerX) / (box.width / 2)
        let dy = abs(Double(point.y) - box.centerY) / (box.height / 2)
        return max(dx, dy)
    }
}
