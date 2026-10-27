//
//  FoodMeasurementPipelineTests.swift
//  GlucoMomentTests
//

import Foundation
import simd
import Testing
@testable import GlucoMoment

@Suite("LiDAR 分割与测量流水线")
struct FoodMeasurementPipelineTests {
    // MARK: - 遮罩栅格

    @Test("栅格尺寸保持图像宽高比")
    func rasterSize() {
        let portrait = FoodMaskRaster.size(forImageSize: SIMD2(1_440, 1_920), longSide: 256)
        let landscape = FoodMaskRaster.size(forImageSize: SIMD2(1_920, 1_440), longSide: 256)

        #expect(portrait.width == 192 && portrait.height == 256)
        #expect(landscape.width == 256 && landscape.height == 192)
    }

    @Test("涂抹与框裁剪")
    func paintingAndRestriction() {
        let empty = FoodMaskRaster(width: 100, height: 100)
        let painted = empty.painting(center: SIMD2(0.5, 0.5), radius: 0.1, value: 1)

        #expect(painted.value(at: SIMD2(0.5, 0.5)) == 1)
        #expect(painted.value(at: SIMD2(0.65, 0.5)) == 0)
        #expect(abs(painted.coveredFraction - Double.pi * 0.01) < 0.005)

        let restricted = painted.restricted(
            to: FoodBoundingBox(minX: 0, minY: 0, maxX: 0.5, maxY: 1),
            padding: 0
        )
        #expect(restricted.value(at: SIMD2(0.45, 0.5)) == 1)
        #expect(restricted.value(at: SIMD2(0.55, 0.5)) == 0)
    }

    @Test("标签栅格补洞并计算质心")
    func labelRasterHolesAndCentroids() {
        var raster = FoodLabelRaster(width: 3, height: 3)
        for (x, y) in [(0, 1), (2, 1), (1, 0), (1, 2)] {
            raster.setLabel(4, at: SIMD2((Float(x) + 0.5) / 3, (Float(y) + 0.5) / 3))
        }
        let filled = raster.dilatingIntoHoles()

        #expect(filled.label(at: SIMD2(0.5, 0.5)) == 4)
        let centroid = filled.centroids()[4]
        #expect(centroid.map { simd_distance($0, SIMD2(0.5, 0.5)) < 1e-5 } == true)
    }

    // MARK: - 格子标注

    @Test("遮罩重叠时叠放的上层食物优先")
    func layeredItemWinsOverlap() {
        let map = makeFlatMap(height: 0.03)
        let points = identityPoints(for: map)
        let rice = FoodDetectedItem(index: 0, name: "米饭", category: .staple, box: fullBox, confidence: 0.9)
        let pork = FoodDetectedItem(
            index: 1, name: "红烧肉", category: .meat, box: centerBox, layeredOnIndex: 0, confidence: 0.9
        )
        let masks = [
            0: FoodMaskRaster(width: 64, height: 64, repeating: 1),
            1: FoodMaskRaster(width: 64, height: 64).painting(center: SIMD2(0.5, 0.5), radius: 0.2, value: 1)
        ]

        let labels = FoodCellLabeler.label(heightMap: map, cellImagePoints: points, masks: masks, items: [rice, pork])
        let centerCell = cell(map, x: 0.5, y: 0.5)
        let cornerCell = cell(map, x: 0.05, y: 0.05)

        #expect(labels[centerCell] == 1)
        #expect(labels[cornerCell] == 0)
    }

    @Test("并排食物的重叠区域按深度断层切分")
    func overlapSplitsAtDepthDiscontinuity() {
        // 左侧食物高 2cm，右侧高 5cm，两者的遮罩在中间 x∈[0.35, 0.65] 重叠。
        let map = makePlaneMap { point in point.x < 0.45 ? 0.02 : 0.05 }
        let points = identityPoints(for: map)
        let left = FoodDetectedItem(
            index: 0, name: "青菜", category: .vegetable,
            box: FoodBoundingBox(minX: 0, minY: 0, maxX: 0.65, maxY: 1), confidence: 0.9
        )
        let right = FoodDetectedItem(
            index: 1, name: "鸡块", category: .meat,
            box: FoodBoundingBox(minX: 0.35, minY: 0, maxX: 1, maxY: 1), confidence: 0.9
        )
        let masks = [
            0: FoodMaskRaster.sampling(width: 100, height: 100) { $0.x <= 0.65 ? 1 : 0 },
            1: FoodMaskRaster.sampling(width: 100, height: 100) { $0.x >= 0.35 ? 1 : 0 }
        ]

        let labels = FoodCellLabeler.label(heightMap: map, cellImagePoints: points, masks: masks, items: [left, right])

        // 按框中心距离会把 x=0.42 判给右侧（右框更宽），但深度连续性应把它判给左侧。
        #expect(labels[cell(map, x: 0.42, y: 0.5)] == 0)
        #expect(labels[cell(map, x: 0.48, y: 0.5)] == 1)
        #expect(labels[cell(map, x: 0.2, y: 0.5)] == 0)
        #expect(labels[cell(map, x: 0.8, y: 0.5)] == 1)
    }

    @Test("收集容器框内的格子")
    func cellsInsideBox() {
        let map = makeFlatMap(height: 0)
        let points = identityPoints(for: map)
        let cells = FoodCellLabeler.cells(
            inside: FoodBoundingBox(minX: 0, minY: 0, maxX: 0.5, maxY: 0.5),
            padding: 0,
            cellImagePoints: points
        )

        #expect(abs(Double(cells.count) / Double(map.cellCount) - 0.25) < 0.02)
    }

    // MARK: - 端到端

    @Test("俯视扫描的红烧肉盖饭：分割、容器与叠放体积")
    func endToEndRiceBowl() throws {
        let scene = RiceBowlScene()
        let output = FoodMeasurementPipeline.run(
            heightMap: scene.heightMap,
            cellImagePoints: scene.cellImagePoints,
            detection: scene.detection,
            masks: scene.masks,
            adjustments: FoodMeasurementAdjustments(),
            overlaySize: (96, 128)
        )

        let bowl = try #require(output.containers[0])
        #expect(bowl.type == .shallowBowl)
        #expect(abs(bowl.rimRadius - 0.08) < 0.006)
        #expect(abs(bowl.rimHeight - 0.05) < 0.003)

        let rice = try #require(output.measurements.first { $0.detection.index == 0 })
        let pork = try #require(output.measurements.first { $0.detection.index == 1 })

        // 红烧肉层厚 1～2cm，名义 1.5cm × 半径 2.5cm 圆面积。
        let porkExpected = Double.pi * 2.5 * 2.5 * 1.5
        #expect(abs(pork.measurement.volumeMilliliters - porkExpected) / porkExpected < 0.12)
        #expect(pork.measurement.volumeMinMilliliters < porkExpected * 0.8)
        #expect(pork.measurement.volumeMaxMilliliters > porkExpected * 1.2)
        #expect(pork.layeredOnName == "米饭")
        #expect(pork.measurement.densitySource == .localTable)

        #expect(rice.measurement.volumeMilliliters > 150)
        #expect(rice.measurement.containerType == .shallowBowl)
        #expect(rice.measurement.measuredGrams > rice.measurement.volumeMilliliters * 0.7)
        #expect(rice.measurement.notes.contains(FoodVolumeNote.partiallyHidden.message))

        #expect(output.labelCentroids[0] != nil)
        #expect(output.labelCentroids[1] != nil)
        let porkCentroid = try #require(output.labelCentroids[1])
        let porkCenterInImage = try #require(scene.capture.orientedImagePoint(forWorldPoint: SIMD3(0.02, 0.055, 0)))
        #expect(simd_distance(porkCentroid, porkCenterInImage) < 0.03)
    }

    @Test("用户调整层厚与容器类型后重新计算")
    func adjustmentsChangeResult() throws {
        let scene = RiceBowlScene()
        var adjustments = FoodMeasurementAdjustments()
        let baseline = FoodMeasurementPipeline.run(
            heightMap: scene.heightMap,
            cellImagePoints: scene.cellImagePoints,
            detection: scene.detection,
            masks: scene.masks,
            adjustments: adjustments,
            overlaySize: (96, 128)
        )

        adjustments.layerThicknessCentimeters[1] = 1.0
        adjustments.containerTypes[0] = .deepBowl
        let adjusted = FoodMeasurementPipeline.run(
            heightMap: scene.heightMap,
            cellImagePoints: scene.cellImagePoints,
            detection: scene.detection,
            masks: scene.masks,
            adjustments: adjustments,
            overlaySize: (96, 128)
        )

        let basePork = try #require(baseline.measurements.first { $0.detection.index == 1 })
        let adjustedPork = try #require(adjusted.measurements.first { $0.detection.index == 1 })
        let baseRice = try #require(baseline.measurements.first { $0.detection.index == 0 })
        let adjustedRice = try #require(adjusted.measurements.first { $0.detection.index == 0 })

        let porkExpected = Double.pi * 2.5 * 2.5 * 1.0
        #expect(abs(adjustedPork.measurement.volumeMilliliters - porkExpected) / porkExpected < 0.12)
        #expect(adjustedPork.measurement.volumeMilliliters < basePork.measurement.volumeMilliliters)
        // 深碗碗底更低，米饭体积更大。
        #expect(adjustedRice.measurement.volumeMilliliters > baseRice.measurement.volumeMilliliters)
        #expect(adjusted.containers[0]?.type == .deepBowl)
    }
}

// MARK: - 测试场景

private let fullBox = FoodBoundingBox(minX: 0, minY: 0, maxX: 1, maxY: 1)
private let centerBox = FoodBoundingBox(minX: 0.3, minY: 0.3, maxX: 0.7, maxY: 0.7)

/// 边长 1m 的单位区域高度图，格子 1cm；平面坐标 (x, z) 直接作为图像坐标使用。
private func makePlaneMap(_ height: (SIMD2<Float>) -> Float) -> PlaneHeightMap {
    let region = PlaneRegion(minX: 0, maxX: 1, minZ: 0, maxZ: 1)
    let cellSize: Float = 0.01
    let count = PlaneHeightMap.cellCount(span: 1, cellSize: cellSize)
    var heights = [Float](repeating: 0, count: count * count)
    for row in 0..<count {
        for column in 0..<count {
            heights[row * count + column] = height(SIMD2((Float(column) + 0.5) * cellSize, (Float(row) + 0.5) * cellSize))
        }
    }
    return PlaneHeightMap(planeTransform: matrix_identity_float4x4, region: region, cellSize: cellSize, heights: heights)
}

private func makeFlatMap(height: Float) -> PlaneHeightMap {
    makePlaneMap { _ in height }
}

private func identityPoints(for map: PlaneHeightMap) -> [SIMD2<Float>?] {
    (0..<map.cellCount).map { Optional(map.cellCenter($0)) }
}

private func cell(_ map: PlaneHeightMap, x: Float, y: Float) -> Int {
    map.cellIndex(atPlanePoint: SIMD2(x, y))!
}

/// 竖屏俯视 50cm 处拍摄的浅碗：碗口半径 8cm、高 5cm，米饭填到 4cm，中心偏右 2cm 处铺着半径 2.5cm 的红烧肉（顶面 5.5cm）。
private struct RiceBowlScene {
    let capture: FoodDepthCapture
    let heightMap: PlaneHeightMap
    let cellImagePoints: [SIMD2<Float>?]
    let detection: FoodDetectionResult
    let masks: [Int: FoodMaskRaster]

    init() {
        let cameraHeight: Float = 0.5
        let transform = simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 0, -1, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, cameraHeight, 0, 1)
        ))
        let projection = CameraProjection(
            intrinsics: simd_float3x3(columns: (SIMD3(1_500, 0, 0), SIMD3(0, 1_500, 0), SIMD3(960, 720, 1))),
            imageSize: SIMD2(1_920, 1_440),
            cameraTransform: transform
        )
        capture = FoodDepthCapture(
            orientedImageData: Data(),
            orientedImageSize: SIMD2(1_440, 1_920),
            imageRotation: .clockwise90,
            bestFrameProjection: projection,
            planeTransform: matrix_identity_float4x4,
            region: .square(center: .zero, halfExtent: 0.15),
            keyframes: []
        )

        let porkCenter = SIMD2<Float>(0.02, 0)
        func surfaceHeight(_ point: SIMD2<Float>) -> Float {
            let distance = simd_length(point)
            if simd_distance(point, porkCenter) <= 0.025 { return 0.055 }
            if distance <= 0.075 { return 0.04 }
            if distance <= 0.08 { return 0.05 }
            return 0
        }

        let region = capture.region
        let cellSize: Float = 0.002
        let count = PlaneHeightMap.cellCount(span: region.width, cellSize: cellSize)
        var heights = [Float](repeating: 0, count: count * count)
        for row in 0..<count {
            for column in 0..<count {
                let point = SIMD2(region.minX + (Float(column) + 0.5) * cellSize, region.minZ + (Float(row) + 0.5) * cellSize)
                heights[row * count + column] = surfaceHeight(point)
            }
        }
        heightMap = PlaneHeightMap(planeTransform: matrix_identity_float4x4, region: region, cellSize: cellSize, heights: heights)
        cellImagePoints = FoodDepthCaptureProcessor.orientedImagePoints(for: heightMap, capture: capture)

        // 由图像坐标反推桌面坐标，生成「完美」分割遮罩。
        let capture = capture
        func planePoint(fromOriented point: SIMD2<Float>, height: Float) -> SIMD2<Float> {
            let sensor = capture.imageRotation.sensorPoint(fromOriented: point) * projection.imageSize
            let world = projection.worldPoint(pixel: sensor, depth: cameraHeight - height)
            return SIMD2(world.x, world.z)
        }
        let riceMask = FoodMaskRaster.sampling(width: 96, height: 128) { point in
            simd_length(planePoint(fromOriented: point, height: 0.04)) <= 0.075 ? 1 : 0
        }
        let porkMask = FoodMaskRaster.sampling(width: 96, height: 128) { point in
            simd_distance(planePoint(fromOriented: point, height: 0.055), porkCenter) <= 0.025 ? 1 : 0
        }
        masks = [0: riceMask, 1: porkMask]

        func box(around center: SIMD2<Float>, radius: Float, height: Float) -> FoodBoundingBox {
            let corners = [SIMD2(-radius, -radius), SIMD2(radius, radius)].compactMap { offset in
                capture.orientedImagePoint(forWorldPoint: SIMD3(center.x + offset.x, height, center.y + offset.y))
            }
            return FoodBoundingBox(
                minX: Double(min(corners[0].x, corners[1].x)),
                minY: Double(min(corners[0].y, corners[1].y)),
                maxX: Double(max(corners[0].x, corners[1].x)),
                maxY: Double(max(corners[0].y, corners[1].y))
            )
        }

        detection = FoodDetectionResult(
            mealName: "红烧肉盖饭",
            items: [
                FoodDetectedItem(
                    index: 0, name: "米饭", category: .staple,
                    box: box(around: .zero, radius: 0.075, height: 0.04),
                    containerIndex: 0, confidence: 0.9
                ),
                FoodDetectedItem(
                    index: 1, name: "红烧肉", category: .meat,
                    box: box(around: porkCenter, radius: 0.025, height: 0.055),
                    containerIndex: 0, layeredOnIndex: 0, layerThicknessCentimeters: 1...2, confidence: 0.9
                )
            ],
            containers: [
                FoodDetectedContainer(index: 0, type: .shallowBowl, box: box(around: .zero, radius: 0.08, height: 0.05))
            ],
            uncertainties: [],
            provider: "test",
            model: "m",
            promptVersion: "v"
        )
    }
}
