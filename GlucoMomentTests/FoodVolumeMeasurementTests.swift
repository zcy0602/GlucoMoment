//
//  FoodVolumeMeasurementTests.swift
//  GlucoMomentTests
//

import Foundation
import simd
import Testing
@testable import GlucoMoment

@Suite("LiDAR 体积测量几何")
struct FoodVolumeMeasurementTests {
    // MARK: - 相机投影

    @Test("反投影后再投影回到同一像素")
    func projectionRoundTrip() throws {
        let projection = makeTopDownProjection(height: 0.5)
        let pixel = SIMD2<Float>(37.5, 150.5)
        let world = projection.worldPoint(pixel: pixel, depth: 0.42)
        let projected = try #require(projection.project(world))

        #expect(simd_distance(projected, pixel) < 1e-3)
    }

    @Test("俯视相机的反投影点落在相机正下方")
    func topDownBackProjection() {
        let projection = makeTopDownProjection(height: 0.5)
        let center = projection.worldPoint(pixel: projection.principalPoint, depth: 0.5)

        #expect(abs(center.x) < 1e-5)
        #expect(abs(center.y) < 1e-5)
        #expect(abs(center.z) < 1e-5)
        #expect(simd_distance(projection.viewingDirection, SIMD3(0, -1, 0)) < 1e-5)
    }

    @Test("内参换算到深度图分辨率后投影一致")
    func scaledIntrinsics() throws {
        let color = CameraProjection(
            intrinsics: simd_float3x3(columns: (SIMD3(1_500, 0, 0), SIMD3(0, 1_500, 0), SIMD3(960, 720, 1))),
            imageSize: SIMD2(1_920, 1_440),
            cameraTransform: makeTopDownProjection(height: 0.5).cameraTransform
        )
        let depth = color.scaled(to: SIMD2(256, 192))
        let world = SIMD3<Float>(0.05, 0, -0.03)
        let colorPixel = try #require(color.project(world))
        let depthPixel = try #require(depth.project(world))

        #expect(simd_distance(colorPixel / SIMD2(1_920, 1_440), depthPixel / SIMD2(256, 192)) < 1e-4)
    }

    @Test("传感器方向与转正图像坐标可以互相换算", arguments: [
        SensorImageRotation.none, .clockwise90, .counterClockwise90, .rotate180
    ])
    func rotationRoundTrip(rotation: SensorImageRotation) {
        let point = SIMD2<Float>(0.2, 0.7)
        let oriented = rotation.orientedPoint(fromSensor: point)
        let restored = rotation.sensorPoint(fromOriented: oriented)

        #expect(simd_distance(restored, point) < 1e-6)
    }

    @Test("顺时针 90° 时传感器左上角映射到转正图像右上角")
    func clockwiseRotationCorner() {
        let oriented = SensorImageRotation.clockwise90.orientedPoint(fromSensor: SIMD2(0, 0))

        #expect(oriented == SIMD2(1, 0))
        #expect(SensorImageRotation.clockwise90.orientedSize(fromSensor: SIMD2(1_920, 1_440)) == SIMD2(1_440, 1_920))
    }

    // MARK: - 多帧融合

    @Test("融合俯视深度帧得到正确的桌面与盒子高度")
    func fusesTopDownDepth() throws {
        let keyframe = makeSyntheticBoxKeyframe(cameraHeight: 0.5, boxHalfWidth: 0.05, boxHeight: 0.04)
        var builder = PlaneHeightMapBuilder(
            planeTransform: matrix_identity_float4x4,
            region: .square(center: .zero, halfExtent: 0.12)
        )
        builder.add(keyframe)
        builder.add(keyframe)
        let heightMap = builder.build().fillingSmallHoles()

        #expect(builder.keyframeCount == 2)
        let boxCell = try #require(heightMap.cellIndex(atPlanePoint: SIMD2(0.01, -0.01)))
        let tableCell = try #require(heightMap.cellIndex(atPlanePoint: SIMD2(0.1, 0.1)))
        let boxHeight = try #require(heightMap.height(at: boxCell))
        let tableHeight = try #require(heightMap.height(at: tableCell))

        #expect(abs(boxHeight - 0.04) < 0.001)
        #expect(abs(tableHeight) < 0.001)
        #expect(heightMap.observedFraction > 0.8)
    }

    @Test("低置信度深度会被过滤")
    func filtersLowConfidence() {
        let keyframe = makeSyntheticBoxKeyframe(cameraHeight: 0.5, boxHalfWidth: 0.05, boxHeight: 0.04, confidence: 0)
        var builder = PlaneHeightMapBuilder(
            planeTransform: matrix_identity_float4x4,
            region: .square(center: .zero, halfExtent: 0.12)
        )
        builder.add(keyframe)

        #expect(builder.sampleCount == 0)
        #expect(builder.build().observedFraction == 0)
    }

    @Test("估计桌面偏移并校正高度")
    func estimatesTableOffset() throws {
        var map = makeHeightMap { _ in 0.0049 }
        map = map.offsettingHeights(by: map.estimatedTableOffset())
        let height = try #require(map.height(at: 0))

        #expect(abs(height) < 0.0011)
    }

    // MARK: - 体积积分

    @Test("圆柱体体积误差小于 3%")
    func cylinderVolume() throws {
        let radius: Float = 0.05
        let height: Float = 0.04
        let map = makeHeightMap { point in simd_length(point) <= radius ? height : 0 }
        let labels = makeLabels(map) { point in simd_length(point) <= radius ? 0 : -1 }

        let result = try #require(
            FoodVolumeEstimator().estimate(
                heightMap: map,
                cellLabels: labels,
                items: [FoodVolumeItem(label: 0, containerIndex: nil, layering: nil)],
                containers: []
            ).first
        )

        let expected = Double.pi * 25 * 4 // 毫升
        #expect(abs(result.volumeMilliliters - expected) / expected < 0.03)
        #expect(result.volumeMinMilliliters < result.volumeMilliliters)
        #expect(result.volumeMaxMilliliters > result.volumeMilliliters)
        #expect(abs(result.meanHeightCentimeters - 4) < 0.15)
        #expect(result.coverage == 1)
        #expect(result.notes.isEmpty)
    }

    @Test("装满的碗体积与幂函数内壁公式一致", arguments: [
        (FoodContainerType.shallowBowl, ContainerGeometry.Preset.shallowBowlProfileExponent),
        (FoodContainerType.deepBowl, ContainerGeometry.Preset.deepBowlProfileExponent)
    ])
    func filledBowlVolume(type: FoodContainerType, exponent: Float) throws {
        let bowl = ContainerGeometry(type: type, center: .zero, rimRadius: 0.08, measuredRimHeight: 0.05)
        let map = makeHeightMap { point in simd_length(point) <= 0.08 ? 0.05 : 0 }
        let labels = makeLabels(map) { point in simd_length(point) <= 0.08 ? 0 : -1 }

        let result = try #require(
            FoodVolumeEstimator().estimate(
                heightMap: map,
                cellLabels: labels,
                items: [FoodVolumeItem(label: 0, containerIndex: 0, layering: nil)],
                containers: [bowl]
            ).first
        )

        // 内底 = 底厚 + d·(r/a)^p，装满时 V = πa²d·p/(p+2)，a 为内半径，d 为内部深度。
        let a = Double(bowl.innerRadius)
        let d = Double(bowl.interiorDepth)
        let p = Double(exponent)
        let expected = Double.pi * a * a * d * p / (p + 2) * 1_000_000
        #expect(abs(result.volumeMilliliters - expected) / expected < 0.03)
        #expect(result.notes.contains(.containerShapeAssumed))
    }

    @Test("同样碗口尺寸下深碗比浅碗装得更多")
    func deepBowlHoldsMore() throws {
        let shallow = ContainerGeometry(type: .shallowBowl, center: .zero, rimRadius: 0.07, measuredRimHeight: 0.06)
        let deep = shallow.with(type: .deepBowl)
        let point = SIMD2<Float>(0.03, 0)

        let shallowBottom = try #require(shallow.innerBottomHeight(at: point))
        let deepBottom = try #require(deep.innerBottomHeight(at: point))
        #expect(deepBottom < shallowBottom)
    }

    @Test("以平盘为底时扣除盘心厚度")
    func plateBaseIsSubtracted() throws {
        let plate = ContainerGeometry(type: .flatPlate, center: .zero, rimRadius: 0.12, measuredRimHeight: 0.02)
        let map = makeHeightMap { point in simd_length(point) <= 0.05 ? 0.036 : 0.006 }
        let labels = makeLabels(map) { point in simd_length(point) <= 0.05 ? 0 : -1 }

        let result = try #require(
            FoodVolumeEstimator().estimate(
                heightMap: map,
                cellLabels: labels,
                items: [FoodVolumeItem(label: 0, containerIndex: 0, layering: nil)],
                containers: [plate]
            ).first
        )

        let expected = Double.pi * 25 * 3
        #expect(abs(result.volumeMilliliters - expected) / expected < 0.03)
    }

    @Test("叠放时按层厚把高度分给下层食物")
    func layeredFoodSplit() throws {
        // 左半边为可见米饭（高 3cm），右半边为铺在米饭上的肉（总高 4cm，肉层 1～2cm）。
        let map = makeHeightMap { point in point.x < 0 ? 0.03 : 0.04 }
        let labels = makeLabels(map) { point in point.x < 0 ? 0 : 1 }
        let items = [
            FoodVolumeItem(label: 0, containerIndex: nil, layering: nil),
            FoodVolumeItem(
                label: 1,
                containerIndex: nil,
                layering: FoodLayering(underlyingLabel: 0, thicknessMin: 0.01, thicknessMax: 0.02)
            )
        ]

        let results = FoodVolumeEstimator(heightNoise: 0).estimate(
            heightMap: map,
            cellLabels: labels,
            items: items,
            containers: []
        )
        let rice = try #require(results.first { $0.label == 0 })
        let meat = try #require(results.first { $0.label == 1 })

        let halfArea = Double(map.cellArea) * Double(map.cellCount) / 2 * 1_000_000 // m² × 1e6，乘以米得到毫升
        #expect(abs(meat.volumeMilliliters - halfArea * 0.015) / (halfArea * 0.015) < 0.01)
        #expect(abs(rice.volumeMilliliters - halfArea * (0.03 + 0.025)) / (halfArea * 0.055) < 0.01)
        #expect(meat.volumeMinMilliliters <= halfArea * 0.01 + 0.5)
        #expect(meat.volumeMaxMilliliters >= halfArea * 0.02 - 0.5)
        #expect(rice.footprintAreaSquareCentimeters > meat.footprintAreaSquareCentimeters * 1.9)
        #expect(meat.notes.contains(.layeredOnTop))
        #expect(rice.notes.contains(.partiallyHidden))
    }

    @Test("用户指定层厚后上层体积按指定值计算")
    func userLayerThickness() throws {
        let map = makeHeightMap { _ in 0.04 }
        let labels = makeLabels(map) { _ in 1 }
        let items = [
            FoodVolumeItem(label: 0, containerIndex: nil, layering: nil),
            FoodVolumeItem(
                label: 1,
                containerIndex: nil,
                layering: FoodLayering(underlyingLabel: 0, thicknessMin: 0.01, thicknessMax: 0.02, userThickness: 0.012)
            )
        ]

        let results = FoodVolumeEstimator(heightNoise: 0).estimate(
            heightMap: map,
            cellLabels: labels,
            items: items,
            containers: []
        )
        let meat = try #require(results.first { $0.label == 1 })
        let area = Double(map.cellArea) * Double(map.cellCount) * 1_000_000

        #expect(abs(meat.volumeMilliliters - area * 0.012) / (area * 0.012) < 0.01)
    }

    @Test("缺失深度按平均高度补全并降低覆盖率")
    func fillsMissingDepth() throws {
        let radius: Float = 0.05
        var toggle = false
        let map = makeHeightMap { point in
            guard simd_length(point) <= radius else { return 0 }
            toggle.toggle()
            return toggle ? 0.04 : .nan
        }
        let labels = makeLabels(map) { point in simd_length(point) <= radius ? 0 : -1 }

        let result = try #require(
            FoodVolumeEstimator().estimate(
                heightMap: map,
                cellLabels: labels,
                items: [FoodVolumeItem(label: 0, containerIndex: nil, layering: nil)],
                containers: []
            ).first
        )

        let expected = Double.pi * 25 * 4
        #expect(abs(result.volumeMilliliters - expected) / expected < 0.03)
        #expect(abs(result.coverage - 0.5) < 0.02)
        #expect(result.notes.contains(.lowCoverage))
        #expect(result.volumeMaxMilliliters - result.volumeMinMilliliters > expected * 0.4)
    }

    @Test("没有像素的食物返回零体积")
    func emptyItem() throws {
        let map = makeHeightMap { _ in 0 }
        let labels = makeLabels(map) { _ in -1 }
        let result = try #require(
            FoodVolumeEstimator().estimate(
                heightMap: map,
                cellLabels: labels,
                items: [FoodVolumeItem(label: 3, containerIndex: nil, layering: nil)],
                containers: []
            ).first
        )

        #expect(result.volumeMilliliters == 0)
        #expect(result.coverage == 0)
        #expect(result.notes.contains(.smallPortion))
    }

    // MARK: - 容器

    @Test("从高度图估计碗口圆心、半径和高度")
    func estimatesRim() throws {
        let center = SIMD2<Float>(0.01, -0.02)
        let map = makeHeightMap { point in
            let distance = simd_distance(point, center)
            if distance <= 0.075 { return 0.04 }
            if distance <= 0.08 { return 0.05 }
            return 0
        }
        let cells = Array(0..<map.cellCount)
        let rim = try #require(ContainerRimEstimator.estimate(in: map, cells: cells, type: .shallowBowl))

        #expect(simd_distance(rim.center, center) < 0.003)
        #expect(abs(rim.rimRadius - 0.08) < 0.005)
        #expect(abs(rim.rimHeight - 0.05) < 0.002)
    }

    @Test("没有可信碗口高度时按预设深径比推算")
    func presetBowlDepth() {
        let deepBowl = ContainerGeometry(type: .deepBowl, center: .zero, rimRadius: 0.064, measuredRimHeight: nil)
        let expected = ContainerGeometry.Preset.bowlBaseThickness
            + ContainerGeometry.Preset.deepBowlDepthRatio * 2 * deepBowl.innerRadius

        #expect(abs(deepBowl.rimHeight - expected) < 1e-6)
        #expect(deepBowl.innerBottomHeight(at: SIMD2(0.2, 0)) == nil)
        #expect(deepBowl.innerBottomHeight(at: .zero) == ContainerGeometry.Preset.bowlBaseThickness)
    }

    @Test("碗内底从中心向碗壁单调升高")
    func bowlBottomRisesTowardRim() throws {
        let bowl = ContainerGeometry(type: .deepBowl, center: .zero, rimRadius: 0.06, measuredRimHeight: 0.07)
        let samples = try stride(from: Float(0), through: 0.05, by: 0.01).map { radius in
            try #require(bowl.innerBottomHeight(at: SIMD2(radius, 0)))
        }

        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 < $1 })
        #expect(samples.last! <= bowl.rimHeight)
    }

    @Test("切换容器类型时保留原始实测碗口高度")
    func changingContainerTypeKeepsMeasurement() {
        let plate = ContainerGeometry(type: .flatPlate, center: .zero, rimRadius: 0.08, measuredRimHeight: 0.05)
        let bowl = plate.with(type: .shallowBowl)

        #expect(bowl.rimHeight == 0.05)
        #expect(bowl.measuredRimHeight == 0.05)
    }

    // MARK: - 密度与克重

    @Test("本地密度表命中常见主食")
    func densityTableHit() {
        let rice = FoodDensityTable.resolve(name: "白米饭", category: .staple, modelRange: 0.5...0.6)

        #expect(rice.source == .localTable)
        #expect(rice.minimum == 0.75)
        #expect(rice.maximum == 0.9)
    }

    @Test("多个别名命中时优先最长别名")
    func densityPrefersLongestAlias() throws {
        let entry = try #require(FoodDensityTable.entry(matching: "番茄炒蛋"))

        #expect(entry.minimum == 0.75)
        #expect(entry.maximum == 0.95)
    }

    @Test("未命中时使用模型区间并限制在合理范围")
    func densityFallsBackToModel() {
        let density = FoodDensityTable.resolve(name: "神秘料理", category: .other, modelRange: 0.05...3)

        #expect(density.source == .model)
        #expect(density.minimum == FoodDensityTable.plausibleRange.lowerBound)
        #expect(density.maximum == FoodDensityTable.plausibleRange.upperBound)
    }

    @Test("模型也没有给出密度时使用类别默认值")
    func densityFallsBackToCategory() {
        let density = FoodDensityTable.resolve(name: "未知菜品", category: .soup, modelRange: nil)

        #expect(density.source == .categoryDefault)
        #expect(density.nominal > 0.98)
    }

    @Test("克重区间由体积区间与密度区间组合而成")
    func measurementCombinesVolumeAndDensity() {
        let volume = FoodVolumeResult(
            label: 0,
            volumeMilliliters: 200,
            volumeMinMilliliters: 180,
            volumeMaxMilliliters: 230,
            footprintAreaSquareCentimeters: 80,
            meanHeightCentimeters: 2.5,
            coverage: 0.9,
            notes: [.containerShapeAssumed]
        )
        let density = FoodDensityEstimate(minimum: 0.75, maximum: 0.9, source: .localTable)
        let measurement = FoodMeasurementBuilder.makeMeasurement(
            volume: volume,
            containerType: .shallowBowl,
            density: density
        )

        #expect(measurement.method == .lidarMeasured)
        #expect(abs(measurement.measuredGrams - 165) < 1e-9)
        #expect(abs(measurement.measuredGramsMin - 135) < 1e-9)
        #expect(abs(measurement.measuredGramsMax - 207) < 1e-9)
        #expect(measurement.notes == [FoodVolumeNote.containerShapeAssumed.message])
    }
}

// MARK: - 测试辅助

/// 在 y = height 处朝正下方观察的相机，深度图 256×192，fx = fy = 200。
private func makeTopDownProjection(height: Float) -> CameraProjection {
    // 相机 x 轴 = 世界 +x，相机 y 轴 = 世界 -z，相机 z 轴 = 世界 +y（沿 -z 观察即朝下）。
    let transform = simd_float4x4(columns: (
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 0, -1, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, height, 0, 1)
    ))
    return CameraProjection(
        intrinsics: simd_float3x3(columns: (SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(128, 96, 1))),
        imageSize: SIMD2(256, 192),
        cameraTransform: transform
    )
}

/// 生成俯视桌面上一个方形盒子的合成深度帧（忽略盒子侧壁）。
private func makeSyntheticBoxKeyframe(
    cameraHeight: Float,
    boxHalfWidth: Float,
    boxHeight: Float,
    confidence: UInt8 = 2
) -> DepthKeyframe {
    let projection = makeTopDownProjection(height: cameraHeight)
    let width = 256
    let height = 192
    var depth = [Float](repeating: 0, count: width * height)

    for row in 0..<height {
        for column in 0..<width {
            let normalized = (SIMD2<Float>(Float(column) + 0.5, Float(row) + 0.5) - projection.principalPoint)
                / projection.focalLength
            // 射线方向在世界坐标中为 (a, -1, b)，其中 a = nx，b = ny（相机 y 轴对应世界 -z）。
            let topDepth = cameraHeight - boxHeight
            let hitX = normalized.x * topDepth
            let hitZ = normalized.y * topDepth
            let hitsBox = abs(hitX) <= boxHalfWidth && abs(hitZ) <= boxHalfWidth
            depth[row * width + column] = hitsBox ? topDepth : cameraHeight
        }
    }

    return DepthKeyframe(
        width: width,
        height: height,
        depth: depth,
        confidence: [UInt8](repeating: confidence, count: width * height),
        projection: projection
    )
}

/// 以原点为中心、边长 30cm、2mm 格子的高度图。
private func makeHeightMap(_ height: (SIMD2<Float>) -> Float) -> PlaneHeightMap {
    let region = PlaneRegion.square(center: .zero, halfExtent: 0.15)
    let cellSize: Float = 0.002
    let columns = PlaneHeightMap.cellCount(span: region.width, cellSize: cellSize)
    let rows = PlaneHeightMap.cellCount(span: region.depth, cellSize: cellSize)
    var heights = [Float](repeating: 0, count: columns * rows)
    for row in 0..<rows {
        for column in 0..<columns {
            let point = SIMD2(
                region.minX + (Float(column) + 0.5) * cellSize,
                region.minZ + (Float(row) + 0.5) * cellSize
            )
            heights[row * columns + column] = height(point)
        }
    }
    return PlaneHeightMap(planeTransform: matrix_identity_float4x4, region: region, cellSize: cellSize, heights: heights)
}

private func makeLabels(_ map: PlaneHeightMap, _ label: (SIMD2<Float>) -> Int32) -> [Int32] {
    (0..<map.cellCount).map { label(map.cellCenter($0)) }
}
