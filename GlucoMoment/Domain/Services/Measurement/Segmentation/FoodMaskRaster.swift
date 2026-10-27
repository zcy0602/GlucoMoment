//
//  FoodMaskRaster.swift
//  GlucoMoment
//

import Foundation
import simd

/// 单个食物的分割遮罩，位于转正图像的归一化坐标中（左上角原点），按行优先存储 0...1 的值。
/// 分辨率与 Vision 输出无关，固定为较小的栅格，便于快速查询和用户修正。
nonisolated struct FoodMaskRaster: Sendable, Hashable {
    let width: Int
    let height: Int
    private(set) var values: [Float]

    init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height, "遮罩尺寸不匹配")
        self.width = width
        self.height = height
        self.values = values
    }

    init(width: Int, height: Int, repeating value: Float = 0) {
        self.init(width: width, height: height, values: [Float](repeating: value, count: width * height))
    }

    /// 以像素中心的归一化坐标逐点采样生成遮罩。
    static func sampling(width: Int, height: Int, _ sample: (SIMD2<Float>) -> Float) -> FoodMaskRaster {
        var values = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let point = SIMD2((Float(column) + 0.5) / Float(width), (Float(row) + 0.5) / Float(height))
                values[row * width + column] = sample(point)
            }
        }
        return FoodMaskRaster(width: width, height: height, values: values)
    }

    /// 按长边像素数计算与图像宽高比一致的栅格尺寸。
    static func size(forImageSize imageSize: SIMD2<Float>, longSide: Int) -> (width: Int, height: Int) {
        guard imageSize.x > 0, imageSize.y > 0 else { return (longSide, longSide) }
        if imageSize.x >= imageSize.y {
            return (longSide, max(1, Int((Float(longSide) * imageSize.y / imageSize.x).rounded())))
        }
        return (max(1, Int((Float(longSide) * imageSize.x / imageSize.y).rounded())), longSide)
    }

    /// 最近邻查询；超出范围返回 0。
    func value(at point: SIMD2<Float>) -> Float {
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return 0 }
        let column = min(width - 1, Int(point.x * Float(width)))
        let row = min(height - 1, Int(point.y * Float(height)))
        return values[row * width + column]
    }

    /// 把以 `center` 为圆心、`radius`（相对于图像短边）为半径的圆形区域设为指定值，用于点按修正。
    func painting(center: SIMD2<Float>, radius: Float, value: Float) -> FoodMaskRaster {
        var painted = self
        let shortSide = Float(min(width, height))
        let radiusPixels = radius * shortSide
        let centerPixel = SIMD2(center.x * Float(width), center.y * Float(height))

        let minColumn = max(0, Int(centerPixel.x - radiusPixels))
        let maxColumn = min(width - 1, Int(centerPixel.x + radiusPixels))
        let minRow = max(0, Int(centerPixel.y - radiusPixels))
        let maxRow = min(height - 1, Int(centerPixel.y + radiusPixels))
        guard minColumn <= maxColumn, minRow <= maxRow else { return painted }

        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                let pixel = SIMD2(Float(column) + 0.5, Float(row) + 0.5)
                if simd_distance(pixel, centerPixel) <= radiusPixels {
                    painted.values[row * width + column] = value
                }
            }
        }
        return painted
    }

    /// 只保留框内（可外扩一定比例）的部分。
    func restricted(to box: FoodBoundingBox, padding: Double = 0.03) -> FoodMaskRaster {
        let minX = Float(box.minX - padding)
        let maxX = Float(box.maxX + padding)
        let minY = Float(box.minY - padding)
        let maxY = Float(box.maxY + padding)

        var restricted = self
        for row in 0..<height {
            let y = (Float(row) + 0.5) / Float(height)
            for column in 0..<width {
                let x = (Float(column) + 0.5) / Float(width)
                if x < minX || x > maxX || y < minY || y > maxY {
                    restricted.values[row * width + column] = 0
                }
            }
        }
        return restricted
    }

    var coveredFraction: Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.count(where: { $0 > 0.5 })) / Double(values.count)
    }
}

/// 每个像素归属的食物序号（-1 表示非食物），用于在照片上叠加彩色遮罩。
nonisolated struct FoodLabelRaster: Sendable, Hashable {
    let width: Int
    let height: Int
    private(set) var labels: [Int32]

    init(width: Int, height: Int, labels: [Int32]) {
        precondition(labels.count == width * height, "标签栅格尺寸不匹配")
        self.width = width
        self.height = height
        self.labels = labels
    }

    init(width: Int, height: Int) {
        self.init(width: width, height: height, labels: [Int32](repeating: -1, count: width * height))
    }

    func label(at point: SIMD2<Float>) -> Int32 {
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return -1 }
        let column = min(width - 1, Int(point.x * Float(width)))
        let row = min(height - 1, Int(point.y * Float(height)))
        return labels[row * width + column]
    }

    mutating func setLabel(_ label: Int32, at point: SIMD2<Float>) {
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return }
        let column = min(width - 1, Int(point.x * Float(width)))
        let row = min(height - 1, Int(point.y * Float(height)))
        labels[row * width + column] = label
    }

    /// 填补被已标注像素包围的空像素（取 4 邻域中出现最多的标签），弥补投影造成的稀疏孔洞。
    func dilatingIntoHoles() -> FoodLabelRaster {
        var result = self
        for row in 0..<height {
            for column in 0..<width where labels[row * width + column] < 0 {
                var counts: [Int32: Int] = [:]
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let x = column + dx
                    let y = row + dy
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let neighbor = labels[y * width + x]
                    if neighbor >= 0 {
                        counts[neighbor, default: 0] += 1
                    }
                }
                if let best = counts.max(by: { $0.value < $1.value }), best.value >= 3 {
                    result.labels[row * width + column] = best.key
                }
            }
        }
        return result
    }

    /// 各标签像素的质心（归一化坐标），用于放置体积标注。
    func centroids() -> [Int32: SIMD2<Float>] {
        var sums: [Int32: (SIMD2<Float>, Int)] = [:]
        for row in 0..<height {
            for column in 0..<width {
                let label = labels[row * width + column]
                guard label >= 0 else { continue }
                let point = SIMD2((Float(column) + 0.5) / Float(width), (Float(row) + 0.5) / Float(height))
                let current = sums[label] ?? (.zero, 0)
                sums[label] = (current.0 + point, current.1 + 1)
            }
        }
        return sums.mapValues { $0.0 / Float($0.1) }
    }
}
