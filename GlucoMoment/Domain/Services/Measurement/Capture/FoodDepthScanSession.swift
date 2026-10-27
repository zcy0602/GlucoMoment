//
//  FoodDepthScanSession.swift
//  GlucoMoment
//

import ARKit
import CoreImage
import Foundation
import Observation
import simd
import UIKit

nonisolated enum FoodDepthScanPhase: Equatable, Sendable {
    case idle
    case searchingSurface
    case ready
    case scanning(progress: Double)
    case processing
    case finished
    case failed(String)
}

nonisolated enum FoodDepthScanGuidance: Equatable, Sendable {
    case findSurface
    case aimAtFood
    case moveSlower
    case moveCloser
    case moveFarther
    case improveLighting
    case trackingLimited
    case keepScanning
    case done

    var message: String {
        switch self {
        case .findSurface:
            "对准放餐食的桌面，缓慢左右移动手机"
        case .aimAtFood:
            "已识别桌面，把餐食放在画面中央后开始扫描"
        case .moveSlower:
            "移动得太快了，请放慢一些"
        case .moveCloser:
            "离餐食太远，请靠近一些（约 30～60 厘米）"
        case .moveFarther:
            "离餐食太近，请稍微拿远一些"
        case .improveLighting:
            "光线不足，请换到更亮的地方"
        case .trackingLimited:
            "正在定位，请保持手机稳定"
        case .keepScanning:
            "在餐食上方缓慢画一个小圈"
        case .done:
            "扫描完成"
        }
    }
}

/// 管理 LiDAR 扫描：锁定桌面平面 → 2～3 秒内采集深度关键帧 → 选出最接近俯视的一帧作为识别图像。
@MainActor
@Observable
final class FoodDepthScanSession: NSObject {
    enum Configuration {
        static let scanDuration: TimeInterval = 3
        static let keyframeInterval: TimeInterval = 0.15
        static let maximumKeyframes = 24
        static let minimumKeyframes = 6
        /// 超过该速度（米/秒）的帧不采用，避免运动模糊。
        static let maximumKeyframeSpeed: Float = 0.35
        static let warningSpeed: Float = 0.25
        static let preferredDistance: ClosedRange<Float> = 0.22...0.85
        static let minimumAmbientIntensity: CGFloat = 150
    }

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    private(set) var phase: FoodDepthScanPhase = .idle
    private(set) var guidance: FoodDepthScanGuidance = .findSurface
    private(set) var capture: FoodDepthCapture?
    private(set) var keyframeCount = 0

    /// 由预览视图在布局时更新，用于决定最佳帧的旋转方向。
    var interfaceOrientation: UIInterfaceOrientation = .portrait

    @ObservationIgnored private weak var session: ARSession?
    @ObservationIgnored private var planeIdentifier: UUID?
    @ObservationIgnored private var lastPlaneSearch: TimeInterval = 0
    @ObservationIgnored private var scanStart: TimeInterval?
    @ObservationIgnored private var lastKeyframeTime: TimeInterval = 0
    @ObservationIgnored private var lastCameraPosition: SIMD3<Float>?
    @ObservationIgnored private var lastFrameTime: TimeInterval?
    @ObservationIgnored private var keyframes: [DepthKeyframe] = []
    @ObservationIgnored private var bestImage: CGImage?
    @ObservationIgnored private var bestProjection: CameraProjection?
    @ObservationIgnored private var bestAngle: Float = .greatestFiniteMagnitude
    @ObservationIgnored private var lastBestUpdate: TimeInterval = 0
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private let imageContext = CIContext()

    func attach(to session: ARSession) {
        self.session = session
        session.delegate = self
    }

    func start() {
        guard let session else { return }
        guard Self.isSupported else {
            phase = .failed("当前设备不支持 LiDAR 扫描。")
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        var semantics: ARConfiguration.FrameSemantics = [.sceneDepth]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            semantics.insert(.smoothedSceneDepth)
        }
        configuration.frameSemantics = semantics

        resetScanState()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        phase = .searchingSurface
        guidance = .findSurface
    }

    func pause() {
        processingTask?.cancel()
        session?.pause()
    }

    /// 重新扫描：保留已锁定的桌面，只清空关键帧。
    func restart() {
        processingTask?.cancel()
        capture = nil
        clearKeyframes()
        if planeIdentifier != nil {
            phase = .ready
            guidance = .aimAtFood
        } else {
            start()
        }
    }

    func beginScan() {
        guard phase == .ready else { return }
        clearKeyframes()
        scanStart = nil
        phase = .scanning(progress: 0)
        guidance = .keepScanning
    }

    /// 提前结束扫描（关键帧数量足够时）。
    func finishScan() {
        guard case .scanning = phase else { return }
        guard keyframes.count >= Configuration.minimumKeyframes else {
            guidance = .keepScanning
            return
        }
        completeScan()
    }

    // MARK: - 帧处理

    private func handle(_ frame: ARFrame) {
        let camera = frame.camera
        let position = SIMD3(camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
        let speed = cameraSpeed(position: position, timestamp: frame.timestamp)

        switch phase {
        case .searchingSurface:
            updateTablePlane(frame)
        case .ready:
            updateTablePlane(frame)
            updateGuidance(frame: frame, speed: speed, scanning: false)
        case .scanning:
            processScanningFrame(frame, speed: speed)
        case .idle, .processing, .finished, .failed:
            break
        }
    }

    private func processScanningFrame(_ frame: ARFrame, speed: Float) {
        let start = scanStart ?? frame.timestamp
        scanStart = start
        let elapsed = frame.timestamp - start
        phase = .scanning(progress: min(1, elapsed / Configuration.scanDuration))
        updateGuidance(frame: frame, speed: speed, scanning: true)

        if case .normal = frame.camera.trackingState,
           speed <= Configuration.maximumKeyframeSpeed,
           frame.timestamp - lastKeyframeTime >= Configuration.keyframeInterval,
           keyframes.count < Configuration.maximumKeyframes,
           let plane = currentPlane(in: frame),
           let keyframe = makeKeyframe(from: frame) {
            lastKeyframeTime = frame.timestamp
            keyframes.append(keyframe)
            keyframeCount = keyframes.count
            considerBestFrame(frame, planeTransform: plane.transform)
        }

        let reachedDuration = elapsed >= Configuration.scanDuration && keyframes.count >= Configuration.minimumKeyframes
        if reachedDuration || keyframes.count >= Configuration.maximumKeyframes {
            completeScan()
        }
    }

    private func updateGuidance(frame: ARFrame, speed: Float, scanning: Bool) {
        if case .limited = frame.camera.trackingState {
            guidance = .trackingLimited
            return
        }
        if let intensity = frame.lightEstimate?.ambientIntensity, intensity < Configuration.minimumAmbientIntensity {
            guidance = .improveLighting
            return
        }
        if speed > Configuration.warningSpeed {
            guidance = .moveSlower
            return
        }
        if let plane = currentPlane(in: frame) {
            let distance = heightAbovePlane(camera: frame.camera, planeTransform: plane.transform)
            if distance > Configuration.preferredDistance.upperBound {
                guidance = .moveCloser
                return
            }
            if distance < Configuration.preferredDistance.lowerBound {
                guidance = .moveFarther
                return
            }
        }
        guidance = scanning ? .keepScanning : .aimAtFood
    }

    /// 通过画面中心的射线寻找桌面：优先 ARKit 分类为桌子的平面，否则取最低的水平平面几何。
    private func updateTablePlane(_ frame: ARFrame) {
        guard let session, frame.timestamp - lastPlaneSearch > 0.3 else { return }
        lastPlaneSearch = frame.timestamp

        let query = frame.raycastQuery(
            from: CGPoint(x: 0.5, y: 0.5),
            allowing: .existingPlaneGeometry,
            alignment: .horizontal
        )
        let planes = session.raycast(query).compactMap { $0.anchor as? ARPlaneAnchor }
        let cameraHeight = frame.camera.transform.columns.3.y
        let candidates = planes.filter { plane in
            let drop = cameraHeight - plane.transform.columns.3.y
            return drop > 0.12 && drop < 1.2
        }

        let chosen = candidates.first { ARPlaneAnchor.isClassificationSupported && $0.classification == .table }
            ?? candidates.min { $0.transform.columns.3.y < $1.transform.columns.3.y }

        guard let chosen else { return }
        planeIdentifier = chosen.identifier
        if phase == .searchingSurface {
            phase = .ready
            guidance = .aimAtFood
        }
    }

    private func currentPlane(in frame: ARFrame) -> ARPlaneAnchor? {
        guard let planeIdentifier else { return nil }
        return frame.anchors.first { $0.identifier == planeIdentifier } as? ARPlaneAnchor
    }

    private func heightAbovePlane(camera: ARCamera, planeTransform: simd_float4x4) -> Float {
        let local = planeTransform.inverse * camera.transform.columns.3
        return local.y
    }

    private func cameraSpeed(position: SIMD3<Float>, timestamp: TimeInterval) -> Float {
        defer {
            lastCameraPosition = position
            lastFrameTime = timestamp
        }
        guard let lastCameraPosition, let lastFrameTime, timestamp > lastFrameTime else { return 0 }
        return simd_distance(position, lastCameraPosition) / Float(timestamp - lastFrameTime)
    }

    private func makeKeyframe(from frame: ARFrame) -> DepthKeyframe? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let depth = Self.copyPixels(depthData.depthMap, as: Float32.self) else { return nil }
        let confidence = depthData.confidenceMap.flatMap { Self.copyPixels($0, as: UInt8.self) }

        let camera = frame.camera
        let imageProjection = CameraProjection(
            intrinsics: camera.intrinsics,
            imageSize: SIMD2(Float(camera.imageResolution.width), Float(camera.imageResolution.height)),
            cameraTransform: camera.transform
        )
        let depthProjection = imageProjection.scaled(to: SIMD2(Float(depth.width), Float(depth.height)))

        guard confidence == nil || confidence?.values.count == depth.values.count else { return nil }
        return DepthKeyframe(
            width: depth.width,
            height: depth.height,
            depth: depth.values,
            confidence: confidence?.values,
            projection: depthProjection
        )
    }

    /// 视线越接近竖直向下越好；为减少开销，只有明显更好时才更新最佳帧图像。
    private func considerBestFrame(_ frame: ARFrame, planeTransform: simd_float4x4) {
        let camera = frame.camera
        let projection = CameraProjection(
            intrinsics: camera.intrinsics,
            imageSize: SIMD2(Float(camera.imageResolution.width), Float(camera.imageResolution.height)),
            cameraTransform: camera.transform
        )
        let planeNormal = simd_normalize(SIMD3(
            planeTransform.columns.1.x,
            planeTransform.columns.1.y,
            planeTransform.columns.1.z
        ))
        let angle = acos(min(1, max(-1, simd_dot(projection.viewingDirection, -planeNormal))))

        let isFirst = bestImage == nil
        let isClearlyBetter = angle < bestAngle - 0.02 && frame.timestamp - lastBestUpdate > 0.3
        guard isFirst || isClearlyBetter else { return }

        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return }
        bestImage = cgImage
        bestProjection = projection
        bestAngle = angle
        lastBestUpdate = frame.timestamp
    }

    private func completeScan() {
        guard let session,
              let frame = session.currentFrame,
              let plane = currentPlane(in: frame),
              let bestImage,
              let bestProjection else {
            phase = .failed("扫描数据不足，请重新扫描。")
            return
        }

        phase = .processing
        guidance = .done

        let planeTransform = plane.transform
        let keyframes = keyframes
        let rotation = Self.rotation(for: interfaceOrientation)
        let context = imageContext

        processingTask = Task { [weak self] in
            let encoded = await Task.detached(priority: .userInitiated) {
                Self.encodeOrientedJPEG(bestImage, rotation: rotation, context: context)
            }.value
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard let encoded else {
                self.phase = .failed("扫描图像处理失败，请重新扫描。")
                return
            }

            let center = FoodDepthCaptureProcessor.regionCenter(
                projection: bestProjection,
                planeTransform: planeTransform
            )
            self.capture = FoodDepthCapture(
                orientedImageData: encoded.data,
                orientedImageSize: encoded.size,
                imageRotation: rotation,
                bestFrameProjection: bestProjection,
                planeTransform: planeTransform,
                region: .square(center: center, halfExtent: FoodDepthCaptureProcessor.defaultHalfExtent),
                keyframes: keyframes
            )
            self.phase = .finished
            self.session?.pause()
        }
    }

    private func resetScanState() {
        processingTask?.cancel()
        planeIdentifier = nil
        lastPlaneSearch = 0
        capture = nil
        lastCameraPosition = nil
        lastFrameTime = nil
        clearKeyframes()
    }

    private func clearKeyframes() {
        keyframes = []
        keyframeCount = 0
        scanStart = nil
        lastKeyframeTime = 0
        bestImage = nil
        bestProjection = nil
        bestAngle = .greatestFiniteMagnitude
        lastBestUpdate = 0
    }

    // MARK: - 像素与图像工具

    /// ARKit 的 capturedImage 为横向（Home 键在右）。按界面方向换算到转正所需的旋转。
    static func rotation(for orientation: UIInterfaceOrientation) -> SensorImageRotation {
        switch orientation {
        case .portrait, .unknown:
            .clockwise90
        case .portraitUpsideDown:
            .counterClockwise90
        case .landscapeLeft:
            .rotate180
        case .landscapeRight:
            .none
        @unknown default:
            .clockwise90
        }
    }

    nonisolated private static func copyPixels<Pixel>(
        _ buffer: CVPixelBuffer,
        as type: Pixel.Type
    ) -> (width: Int, height: Int, values: [Pixel])? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard bytesPerRow >= width * MemoryLayout<Pixel>.stride else { return nil }

        var values: [Pixel] = []
        values.reserveCapacity(width * height)
        for row in 0..<height {
            let rowPointer = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Pixel.self)
            values.append(contentsOf: UnsafeBufferPointer(start: rowPointer, count: width))
        }
        return (width, height, values)
    }

    nonisolated private static func encodeOrientedJPEG(
        _ image: CGImage,
        rotation: SensorImageRotation,
        context: CIContext
    ) -> (data: Data, size: SIMD2<Float>)? {
        let oriented = CIImage(cgImage: image).oriented(rotation.imageOrientation)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(
                of: oriented,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
              ) else { return nil }
        return (data, SIMD2(Float(oriented.extent.width), Float(oriented.extent.height)))
    }
}

extension FoodDepthScanSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 未设置 delegateQueue 时 ARKit 在主线程回调。
        MainActor.assumeIsolated {
            handle(frame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            phase = .failed("相机会话出错：\(error.localizedDescription)")
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            if case .scanning = phase {
                restart()
            }
        }
    }
}
