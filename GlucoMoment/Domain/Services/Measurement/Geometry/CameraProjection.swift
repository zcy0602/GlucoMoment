//
//  CameraProjection.swift
//  GlucoMoment
//

import CoreGraphics
import ImageIO
import simd

/// 针孔相机模型，遵循 ARKit 约定：相机坐标系 x 向右、y 向上、沿 -z 方向观察；
/// 像素坐标原点在左上角、v 向下。内参矩阵与 `imageSize` 对应同一分辨率。
nonisolated struct CameraProjection: Sendable {
    /// 列主序内参：fx = [0][0]，fy = [1][1]，cx = [2][0]，cy = [2][1]。
    let intrinsics: simd_float3x3
    let imageSize: SIMD2<Float>
    /// 相机到世界坐标的变换。
    let cameraTransform: simd_float4x4

    private let worldToCamera: simd_float4x4

    init(intrinsics: simd_float3x3, imageSize: SIMD2<Float>, cameraTransform: simd_float4x4) {
        self.intrinsics = intrinsics
        self.imageSize = imageSize
        self.cameraTransform = cameraTransform
        worldToCamera = cameraTransform.inverse
    }

    var focalLength: SIMD2<Float> {
        SIMD2(intrinsics[0][0], intrinsics[1][1])
    }

    var principalPoint: SIMD2<Float> {
        SIMD2(intrinsics[2][0], intrinsics[2][1])
    }

    /// 相机在世界坐标中的观察方向（单位向量）。
    var viewingDirection: SIMD3<Float> {
        let forward = -cameraTransform.columns.2
        return simd_normalize(SIMD3(forward.x, forward.y, forward.z))
    }

    var position: SIMD3<Float> {
        let translation = cameraTransform.columns.3
        return SIMD3(translation.x, translation.y, translation.z)
    }

    /// 把内参换算到另一分辨率（例如从彩色图 1920×1440 换算到深度图 256×192）。
    func scaled(to newSize: SIMD2<Float>) -> CameraProjection {
        let scale = newSize / imageSize
        var scaledIntrinsics = intrinsics
        scaledIntrinsics[0][0] *= scale.x
        scaledIntrinsics[1][1] *= scale.y
        scaledIntrinsics[2][0] *= scale.x
        scaledIntrinsics[2][1] *= scale.y
        return CameraProjection(
            intrinsics: scaledIntrinsics,
            imageSize: newSize,
            cameraTransform: cameraTransform
        )
    }

    /// 把像素坐标与该点沿观察方向的深度（米）反投影为世界坐标。
    func worldPoint(pixel: SIMD2<Float>, depth: Float) -> SIMD3<Float> {
        let normalized = (pixel - principalPoint) / focalLength
        let cameraPoint = SIMD4<Float>(normalized.x * depth, -normalized.y * depth, -depth, 1)
        let world = cameraTransform * cameraPoint
        return SIMD3(world.x, world.y, world.z)
    }

    /// 把世界坐标投影到像素坐标；点在相机背后时返回 nil。
    func project(_ worldPoint: SIMD3<Float>) -> SIMD2<Float>? {
        let camera = worldToCamera * SIMD4<Float>(worldPoint, 1)
        let depth = -camera.z
        guard depth > 1e-4 else { return nil }
        let normalized = SIMD2<Float>(camera.x / depth, -camera.y / depth)
        return normalized * focalLength + principalPoint
    }
}

/// 传感器原始方向的图像（ARKit `capturedImage` 为横向）与转正后图像之间的坐标换算。
/// 所有点均为左上角原点、0...1 归一化坐标。
nonisolated enum SensorImageRotation: Sendable, Hashable {
    case none
    /// 顺时针旋转 90°，竖屏握持时的常见情况。
    case clockwise90
    case counterClockwise90
    case rotate180

    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .none:
            .up
        case .clockwise90:
            .right
        case .counterClockwise90:
            .left
        case .rotate180:
            .down
        }
    }

    func orientedPoint(fromSensor point: SIMD2<Float>) -> SIMD2<Float> {
        switch self {
        case .none:
            point
        case .clockwise90:
            SIMD2(1 - point.y, point.x)
        case .counterClockwise90:
            SIMD2(point.y, 1 - point.x)
        case .rotate180:
            SIMD2(1 - point.x, 1 - point.y)
        }
    }

    func sensorPoint(fromOriented point: SIMD2<Float>) -> SIMD2<Float> {
        switch self {
        case .none:
            point
        case .clockwise90:
            SIMD2(point.y, 1 - point.x)
        case .counterClockwise90:
            SIMD2(1 - point.y, point.x)
        case .rotate180:
            SIMD2(1 - point.x, 1 - point.y)
        }
    }

    /// 转正后图像的尺寸。
    func orientedSize(fromSensor size: SIMD2<Float>) -> SIMD2<Float> {
        switch self {
        case .none, .rotate180:
            size
        case .clockwise90, .counterClockwise90:
            SIMD2(size.y, size.x)
        }
    }
}

/// 一帧 LiDAR 深度数据：深度单位为米，按行优先存储。
nonisolated struct DepthKeyframe: Sendable {
    let width: Int
    let height: Int
    let depth: [Float]
    /// ARConfidenceLevel 原始值（0 低、1 中、2 高）；nil 表示全部视为高置信度。
    let confidence: [UInt8]?
    /// 内参已换算到深度图分辨率。
    let projection: CameraProjection

    init(width: Int, height: Int, depth: [Float], confidence: [UInt8]?, projection: CameraProjection) {
        precondition(depth.count == width * height, "深度数据尺寸不匹配")
        precondition(confidence == nil || confidence?.count == width * height, "置信度数据尺寸不匹配")
        self.width = width
        self.height = height
        self.depth = depth
        self.confidence = confidence
        self.projection = projection
    }
}
