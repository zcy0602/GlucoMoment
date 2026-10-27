//
//  MeasuredFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

/// LiDAR 两段式识别：①定位食物与容器 → 本地分割与测量 → ②结合实测份量估算营养。
nonisolated protocol MeasuredFoodAnalysisService: Sendable {
    func detectFoods(
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodDetectionResult

    func estimateNutrition(
        imageData: Data,
        detection: FoodDetectionResult,
        measurements: [FoodMeasuredItem],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult
}

/// 归一化边界框：左上角原点，坐标 0...1，相对于转正后的图像。
nonisolated struct FoodBoundingBox: Hashable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = min(minX, maxX).clamped(to: 0...1)
        self.minY = min(minY, maxY).clamped(to: 0...1)
        self.maxX = max(minX, maxX).clamped(to: 0...1)
        self.maxY = max(minY, maxY).clamped(to: 0...1)
    }

    /// 由模型返回的 0～1000 坐标 [x1, y1, x2, y2] 创建；尺寸过小时返回 nil。
    init?(thousandths values: [Double]) {
        guard values.count == 4, values.allSatisfy(\.isFinite) else { return nil }
        let box = FoodBoundingBox(
            minX: values[0] / 1_000,
            minY: values[1] / 1_000,
            maxX: values[2] / 1_000,
            maxY: values[3] / 1_000
        )
        guard box.width >= 0.01, box.height >= 0.01 else { return nil }
        self = box
    }

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var area: Double { width * height }
    var centerX: Double { (minX + maxX) / 2 }
    var centerY: Double { (minY + maxY) / 2 }

    func contains(x: Double, y: Double) -> Bool {
        (minX...maxX).contains(x) && (minY...maxY).contains(y)
    }

    var thousandths: [Int] {
        [minX, minY, maxX, maxY].map { Int(($0 * 1_000).rounded()) }
    }
}

nonisolated struct FoodDetectedContainer: Identifiable, Hashable, Sendable {
    var index: Int
    var type: FoodContainerType
    var box: FoodBoundingBox

    var id: Int { index }
}

nonisolated struct FoodDetectedItem: Identifiable, Hashable, Sendable {
    let id: UUID
    /// 模型给出的序号，同时作为分割标签。
    var index: Int
    var name: String
    var category: FoodCategory
    var box: FoodBoundingBox
    var containerIndex: Int?
    /// 本食物铺在哪个食物之上（对应其 `index`）。
    var layeredOnIndex: Int?
    var layerThicknessCentimeters: ClosedRange<Double>?
    var densityRange: ClosedRange<Double>?
    var confidence: Double

    init(
        id: UUID = UUID(),
        index: Int,
        name: String,
        category: FoodCategory,
        box: FoodBoundingBox,
        containerIndex: Int? = nil,
        layeredOnIndex: Int? = nil,
        layerThicknessCentimeters: ClosedRange<Double>? = nil,
        densityRange: ClosedRange<Double>? = nil,
        confidence: Double
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.category = category
        self.box = box
        self.containerIndex = containerIndex
        self.layeredOnIndex = layeredOnIndex
        self.layerThicknessCentimeters = layerThicknessCentimeters
        self.densityRange = densityRange
        self.confidence = confidence
    }
}

nonisolated struct FoodDetectionResult: Hashable, Sendable {
    var mealName: String
    var items: [FoodDetectedItem]
    var containers: [FoodDetectedContainer]
    var uncertainties: [String]
    var provider: String
    var model: String
    var promptVersion: String

    func item(index: Int) -> FoodDetectedItem? {
        items.first { $0.index == index }
    }

    func container(index: Int?) -> FoodDetectedContainer? {
        guard let index else { return nil }
        return containers.first { $0.index == index }
    }
}

/// 第二次调用的输入：检测到的食物及其本地测量结果。
nonisolated struct FoodMeasuredItem: Hashable, Sendable {
    var detection: FoodDetectedItem
    var measurement: FoodItemMeasurement
    var layeredOnName: String?
}

nonisolated enum FoodMeasuredResultAssembler {
    /// 把测量结果挂到模型返回的条目上：按 itemIndex 匹配，缺失时按顺序匹配。
    /// 模型克重明显偏离实测区间时追加提示，方便用户检查。
    static func assemble(
        _ result: FoodRecognitionResult,
        itemIndices: [Int?],
        measurements: [FoodMeasuredItem]
    ) -> FoodRecognitionResult {
        var assembled = result
        assembled.measurementMethod = .lidarMeasured

        var unmatched = measurements
        for position in assembled.items.indices {
            let requestedIndex = itemIndices.indices.contains(position) ? itemIndices[position] : nil
            let matchPosition = requestedIndex.flatMap { index in
                unmatched.firstIndex { $0.detection.index == index }
            } ?? (unmatched.isEmpty ? nil : 0)

            guard let matchPosition else { continue }
            let measured = unmatched.remove(at: matchPosition)
            assembled.items[position].id = measured.detection.id
            assembled.items[position].measurement = measured.measurement

            let grams = assembled.items[position].estimatedGrams
            let lower = measured.measurement.measuredGramsMin * 0.8
            let upper = measured.measurement.measuredGramsMax * 1.2
            if grams < lower || grams > upper {
                assembled.items[position].uncertainties.append(
                    "模型估计的重量与 LiDAR 实测区间（\(Int(measured.measurement.measuredGramsMin.rounded()))～\(Int(measured.measurement.measuredGramsMax.rounded()))g）差异较大，请检查"
                )
            }
        }

        return assembled
    }
}
