//
//  FoodSegmentationService.swift
//  GlucoMoment
//

import Foundation
import simd
import Vision

/// 生成每个食物遮罩的具体策略。
nonisolated protocol FoodMaskGenerating: Sendable {
    func initialMasks(for items: [FoodDetectedItem]) async throws -> [Int: FoodMaskRaster]
    /// 基于模型的修正；返回 nil 表示该策略不支持或已达上限，由调用方改用局部涂抹。
    func refinedMask(itemIndex: Int, at point: SIMD2<Float>, include: Bool) async throws -> FoodMaskRaster?
}

nonisolated enum FoodSegmentationMethod: String, Sendable {
    case iterative
    case foregroundBox

    var label: String {
        switch self {
        case .iterative:
            "精细分割"
        case .foregroundBox:
            "前景分割"
        }
    }
}

/// 以 Qwen 检测框为种子生成每个食物的遮罩，并记录用户的点按修正。
actor FoodSegmentationService {
    struct MaskOverride: Sendable, Hashable {
        var center: SIMD2<Float>
        var radius: Float
        var value: Float
    }

    /// 点按修正的涂抹半径（相对于图像短边）。
    static let brushRadius: Float = 0.04

    let method: FoodSegmentationMethod
    private let generator: any FoodMaskGenerating
    private var baseMasks: [Int: FoodMaskRaster] = [:]
    private var overrides: [Int: [MaskOverride]] = [:]

    private init(method: FoodSegmentationMethod, generator: any FoodMaskGenerating) {
        self.method = method
        self.generator = generator
    }

    /// iOS 27 起优先使用迭代分割（需要时下载模型）；不可用或下载失败时退回前景实例遮罩。
    static func make(imageData: Data, imageSize: SIMD2<Float>, rasterLongSide: Int = 256) async -> FoodSegmentationService {
        let size = FoodMaskRaster.size(forImageSize: imageSize, longSide: rasterLongSide)

        if #available(iOS 27.0, *) {
            do {
                try await IterativeFoodMaskGenerator.prepareAssets()
                return FoodSegmentationService(
                    method: .iterative,
                    generator: IterativeFoodMaskGenerator(imageData: imageData, width: size.width, height: size.height)
                )
            } catch {
                // 模型资源不可用时使用降级方案。
            }
        }

        return FoodSegmentationService(
            method: .foregroundBox,
            generator: ForegroundBoxFoodMaskGenerator(imageData: imageData, width: size.width, height: size.height)
        )
    }

    func segment(items: [FoodDetectedItem]) async throws -> [Int: FoodMaskRaster] {
        baseMasks = try await generator.initialMasks(for: items)
        overrides = [:]
        return effectiveMasks()
    }

    /// 把点按位置加入或移出某个食物；加入时同时从其他食物中移除该区域。
    func refine(itemIndex: Int, at point: SIMD2<Float>, include: Bool) async throws -> [Int: FoodMaskRaster] {
        if let refined = try await generator.refinedMask(itemIndex: itemIndex, at: point, include: include) {
            baseMasks[itemIndex] = refined
        } else {
            overrides[itemIndex, default: []].append(
                MaskOverride(center: point, radius: Self.brushRadius, value: include ? 1 : 0)
            )
        }

        if include {
            for other in baseMasks.keys where other != itemIndex {
                overrides[other, default: []].append(
                    MaskOverride(center: point, radius: Self.brushRadius, value: 0)
                )
            }
        }
        return effectiveMasks()
    }

    private func effectiveMasks() -> [Int: FoodMaskRaster] {
        baseMasks.reduce(into: [:]) { result, entry in
            var mask = entry.value
            for override in overrides[entry.key] ?? [] {
                mask = mask.painting(center: override.center, radius: override.radius, value: override.value)
            }
            result[entry.key] = mask
        }
    }
}

// MARK: - 坐标换算

nonisolated extension FoodBoundingBox {
    /// Vision 使用左下角原点的归一化坐标。
    var visionRect: NormalizedRect {
        NormalizedRect(x: minX, y: 1 - maxY, width: width, height: height)
    }

    /// 框的内切椭圆，用于分割失败时的兜底遮罩。
    func inscribedEllipseValue(at point: SIMD2<Float>) -> Float {
        guard width > 0, height > 0 else { return 0 }
        let dx = (Double(point.x) - centerX) / (width / 2)
        let dy = (Double(point.y) - centerY) / (height / 2)
        return dx * dx + dy * dy <= 1 ? 1 : 0
    }
}

nonisolated private func visionPoint(_ point: SIMD2<Float>) -> NormalizedPoint {
    NormalizedPoint(x: Double(point.x), y: Double(1 - point.y))
}

// MARK: - iOS 27：迭代分割

@available(iOS 27.0, *)
actor IterativeFoodMaskGenerator: FoodMaskGenerating {
    private let imageData: Data
    private let width: Int
    private let height: Int
    private var requests: [Int: GenerateIterativeSegmentationRequest] = [:]
    private var boxes: [Int: FoodBoundingBox] = [:]

    init(imageData: Data, width: Int, height: Int) {
        self.imageData = imageData
        self.width = width
        self.height = height
    }

    static func prepareAssets() async throws {
        let probe = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
        switch await probe.assetStatus {
        case .ready:
            return
        case .error(let error):
            throw error
        default:
            try await probe.downloadAssets()
        }
    }

    func initialMasks(for items: [FoodDetectedItem]) async throws -> [Int: FoodMaskRaster] {
        var masks: [Int: FoodMaskRaster] = [:]
        for item in items {
            try Task.checkCancellation()
            let request = GenerateIterativeSegmentationRequest(seedBox: item.box.visionRect)
            request.qualityLevel = .balanced
            requests[item.index] = request
            boxes[item.index] = item.box

            let observation = try await request.perform(on: imageData, orientation: nil)
            let mask = raster(from: observation).restricted(to: item.box, padding: 0.05)
            masks[item.index] = Self.fallbackIfEmpty(mask, box: item.box, width: width, height: height)
        }
        return masks
    }

    func refinedMask(itemIndex: Int, at point: SIMD2<Float>, include: Bool) async throws -> FoodMaskRaster? {
        guard let request = requests[itemIndex], let box = boxes[itemIndex] else { return nil }
        do {
            if include {
                try request.addIncludedPoint(visionPoint(point))
            } else {
                try request.addExcludedPoint(visionPoint(point))
            }
        } catch {
            // 已达到 11 个点的上限。
            return nil
        }

        let observation = try await request.perform(on: imageData, orientation: nil)
        // 用户修正后允许遮罩超出原检测框一定范围。
        return raster(from: observation).restricted(to: box, padding: 0.15)
    }

    private func raster(from observation: PixelBufferObservation?) -> FoodMaskRaster {
        guard let observation else { return FoodMaskRaster(width: width, height: height) }
        let sampled = FoodMaskRaster.sampling(width: width, height: height) { point in
            observation.pixel(at: visionPoint(point))
        }
        // 灰度遮罩可能以 0～255 表示，统一归一化到 0～1。
        let maximum = sampled.values.max() ?? 0
        guard maximum > 1.001 else { return sampled }
        return FoodMaskRaster(width: width, height: height, values: sampled.values.map { $0 / 255 })
    }

    fileprivate static func fallbackIfEmpty(_ mask: FoodMaskRaster, box: FoodBoundingBox, width: Int, height: Int) -> FoodMaskRaster {
        let boxFraction = max(box.area, 1e-6)
        guard mask.coveredFraction / boxFraction < 0.15 else { return mask }
        return FoodMaskRaster.sampling(width: width, height: height) { box.inscribedEllipseValue(at: $0) }
    }
}

// MARK: - iOS 26：前景实例遮罩 ∩ 检测框

actor ForegroundBoxFoodMaskGenerator: FoodMaskGenerating {
    private let imageData: Data
    private let width: Int
    private let height: Int

    init(imageData: Data, width: Int, height: Int) {
        self.imageData = imageData
        self.width = width
        self.height = height
    }

    func initialMasks(for items: [FoodDetectedItem]) async throws -> [Int: FoodMaskRaster] {
        let foreground = try await foregroundRaster()
        var masks: [Int: FoodMaskRaster] = [:]
        for item in items {
            let mask = foreground.map { $0.restricted(to: item.box, padding: 0) }
                ?? FoodMaskRaster(width: width, height: height)
            masks[item.index] = Self.fallbackIfSparse(mask, box: item.box, width: width, height: height)
        }
        return masks
    }

    /// 前景遮罩无法按点细化，改由调用方涂抹。
    func refinedMask(itemIndex: Int, at point: SIMD2<Float>, include: Bool) async throws -> FoodMaskRaster? {
        nil
    }

    private func foregroundRaster() async throws -> FoodMaskRaster? {
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await request.perform(on: imageData, orientation: nil) else { return nil }
        let instances = observation.allInstancesMask
        return FoodMaskRaster.sampling(width: width, height: height) { point in
            instances.pixel(at: visionPoint(point)) > 0.5 ? 1 : 0
        }
    }

    /// 前景检测漏掉食物时（框内覆盖率很低），退回到框的内切椭圆。
    private static func fallbackIfSparse(_ mask: FoodMaskRaster, box: FoodBoundingBox, width: Int, height: Int) -> FoodMaskRaster {
        let boxFraction = max(box.area, 1e-6)
        guard mask.coveredFraction / boxFraction < 0.2 else { return mask }
        return FoodMaskRaster.sampling(width: width, height: height) { box.inscribedEllipseValue(at: $0) }
    }
}
