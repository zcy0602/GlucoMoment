//
//  FoodDepthCapture.swift
//  GlucoMoment
//

import Foundation
import simd

/// 一次 LiDAR 扫描的全部产物：最佳俯视帧（用于识别与分割）、桌面平面以及用于融合的深度关键帧。
nonisolated struct FoodDepthCapture: Sendable {
    /// 已转正的最佳帧 JPEG，直接用于上传与分割。
    let orientedImageData: Data
    /// 转正后图像的像素尺寸。
    let orientedImageSize: SIMD2<Float>
    /// 传感器图像需要如何旋转才能转正。
    let imageRotation: SensorImageRotation
    /// 最佳帧在传感器原始分辨率下的投影模型。
    let bestFrameProjection: CameraProjection
    /// 桌面平面到世界坐标的变换，y 轴为平面法向。
    let planeTransform: simd_float4x4
    /// 高度图覆盖区域（平面坐标）。
    let region: PlaneRegion
    let keyframes: [DepthKeyframe]

    /// 把世界坐标点映射到转正图像的归一化坐标（左上角原点）；不在画面内时返回 nil。
    func orientedImagePoint(forWorldPoint point: SIMD3<Float>) -> SIMD2<Float>? {
        guard let pixel = bestFrameProjection.project(point) else { return nil }
        let normalized = pixel / bestFrameProjection.imageSize
        guard (0...1).contains(normalized.x), (0...1).contains(normalized.y) else { return nil }
        return imageRotation.orientedPoint(fromSensor: normalized)
    }
}

nonisolated enum FoodDepthCaptureProcessor {
    /// 默认高度图范围：以最佳帧视线与桌面的交点为中心、边长 60cm。
    static let defaultHalfExtent: Float = 0.3

    /// 计算最佳帧视线与桌面的交点（平面坐标 x, z）。
    static func regionCenter(projection: CameraProjection, planeTransform: simd_float4x4) -> SIMD2<Float> {
        let worldToPlane = planeTransform.inverse
        let origin4 = worldToPlane * SIMD4<Float>(projection.position, 1)
        let direction4 = worldToPlane * SIMD4<Float>(projection.viewingDirection, 0)
        let origin = SIMD3(origin4.x, origin4.y, origin4.z)
        let direction = SIMD3(direction4.x, direction4.y, direction4.z)

        guard direction.y < -1e-3 else { return SIMD2(origin.x, origin.z) }
        let distance = -origin.y / direction.y
        let hit = origin + direction * distance
        return SIMD2(hit.x, hit.z)
    }

    /// 融合所有关键帧，补小洞，并把桌面校正到高度 0。计算量较大，应在后台调用。
    static func makeHeightMap(from capture: FoodDepthCapture, cellSize: Float = 0.002) -> PlaneHeightMap {
        var builder = PlaneHeightMapBuilder(
            planeTransform: capture.planeTransform,
            region: capture.region,
            cellSize: cellSize
        )
        for keyframe in capture.keyframes {
            builder.add(keyframe)
        }

        let filled = builder.build().fillingSmallHoles(passes: 3)
        return filled.offsettingHeights(by: filled.estimatedTableOffset())
    }

    /// 计算每个高度格子顶面在转正图像中的归一化坐标，用于把图像分割结果映射到高度图。
    static func orientedImagePoints(for heightMap: PlaneHeightMap, capture: FoodDepthCapture) -> [SIMD2<Float>?] {
        (0..<heightMap.cellCount).map { cell in
            let height = heightMap.height(at: cell) ?? 0
            return capture.orientedImagePoint(forWorldPoint: heightMap.worldPoint(cell: cell, height: height))
        }
    }
}
