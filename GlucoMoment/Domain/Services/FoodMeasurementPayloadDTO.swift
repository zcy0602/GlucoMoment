//
//  FoodMeasurementPayloadDTO.swift
//  GlucoMoment
//

import Foundation

// MARK: - 检测阶段响应

nonisolated struct FoodDetectionPayloadDTO: Decodable, Sendable {
    let mealName: String
    let containers: [FoodDetectedContainerDTO]?
    let items: [FoodDetectedItemDTO]
    let uncertainties: [String]?

    /// 校验并规范化模型输出：丢弃无效框、修复越界或成环的引用、补全缺省层厚。
    func makeResult(provider: String, model: String, promptVersion: String) throws -> FoodDetectionResult {
        let trimmedName = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw FoodAnalysisError.invalidResponse }

        var containerIndices = Set<Int>()
        let parsedContainers: [FoodDetectedContainer] = (containers ?? []).compactMap { dto in
            guard let box = FoodBoundingBox(thousandths: dto.box), containerIndices.insert(dto.index).inserted else {
                return nil
            }
            return FoodDetectedContainer(
                index: dto.index,
                type: FoodContainerType(rawValue: dto.type) ?? .flatPlate,
                box: box
            )
        }

        var itemIndices = Set<Int>()
        var parsedItems: [FoodDetectedItem] = items.compactMap { dto in
            let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let box = FoodBoundingBox(thousandths: dto.box),
                  itemIndices.insert(dto.index).inserted else { return nil }

            return FoodDetectedItem(
                index: dto.index,
                name: name,
                category: dto.category.flatMap(FoodCategory.init(rawValue:)) ?? .other,
                box: box,
                containerIndex: dto.containerIndex.flatMap { containerIndices.contains($0) ? $0 : nil },
                layeredOnIndex: dto.layeredOnIndex,
                layerThicknessCentimeters: Self.range(dto.layerThicknessCmMin, dto.layerThicknessCmMax, within: 0.2...10),
                densityRange: Self.range(dto.densityMin, dto.densityMax, within: FoodDensityTable.plausibleRange),
                confidence: (dto.confidence ?? 0.5).clamped(to: 0...1)
            )
        }

        guard !parsedItems.isEmpty, parsedItems.count <= 20 else { throw FoodAnalysisError.invalidResponse }

        // 叠放引用必须指向其他有效食物，且不能互相引用。
        for position in parsedItems.indices {
            guard let under = parsedItems[position].layeredOnIndex else { continue }
            let selfIndex = parsedItems[position].index
            let underItem = parsedItems.first { $0.index == under }
            if under == selfIndex || underItem == nil || underItem?.layeredOnIndex == selfIndex {
                parsedItems[position].layeredOnIndex = nil
                parsedItems[position].layerThicknessCentimeters = nil
            } else if parsedItems[position].layerThicknessCentimeters == nil {
                parsedItems[position].layerThicknessCentimeters = 0.5...2.0
            }
        }
        for position in parsedItems.indices where parsedItems[position].layeredOnIndex == nil {
            parsedItems[position].layerThicknessCentimeters = nil
        }

        return FoodDetectionResult(
            mealName: trimmedName,
            items: parsedItems,
            containers: parsedContainers,
            uncertainties: Array((uncertainties ?? []).prefix(8)),
            provider: provider,
            model: model,
            promptVersion: promptVersion
        )
    }

    private static func range(_ first: Double?, _ second: Double?, within bounds: ClosedRange<Double>) -> ClosedRange<Double>? {
        guard let first, let second, first > 0, second > 0, first.isFinite, second.isFinite else { return nil }
        let lower = min(first, second).clamped(to: bounds)
        let upper = max(first, second).clamped(to: bounds)
        return lower...upper
    }
}

nonisolated struct FoodDetectedContainerDTO: Decodable, Sendable {
    let index: Int
    let type: String
    let box: [Double]
}

nonisolated struct FoodDetectedItemDTO: Decodable, Sendable {
    let index: Int
    let name: String
    let category: String?
    let box: [Double]
    let containerIndex: Int?
    let layeredOnIndex: Int?
    let layerThicknessCmMin: Double?
    let layerThicknessCmMax: Double?
    let densityMin: Double?
    let densityMax: Double?
    let confidence: Double?
}

/// 代理服务器 `/v1/food/detect` 的响应：在检测结构外附带服务端使用的模型信息。
nonisolated struct FoodDetectionProxyResponseDTO: Decodable, Sendable {
    let provider: String
    let model: String
    let promptVersion: String
    let mealName: String
    let containers: [FoodDetectedContainerDTO]?
    let items: [FoodDetectedItemDTO]
    let uncertainties: [String]?

    func makeResult() throws -> FoodDetectionResult {
        try FoodDetectionPayloadDTO(
            mealName: mealName,
            containers: containers,
            items: items,
            uncertainties: uncertainties
        ).makeResult(provider: provider, model: model, promptVersion: promptVersion)
    }
}

// MARK: - 估算阶段请求

/// 发送给模型（或代理服务器）的实测报告，数值保留一位小数以节省 token。
nonisolated struct FoodMeasurementReportDTO: Encodable, Sendable {
    struct Item: Encodable, Sendable {
        let itemIndex: Int
        let name: String
        let category: String
        let containerType: String
        let layeredOnIndex: Int?
        let layeredOnName: String?
        let volumeMl: Double
        let volumeMinMl: Double
        let volumeMaxMl: Double
        let footprintAreaCm2: Double
        let meanHeightCm: Double
        let coverage: Double
        let densityGPerMl: Double
        let densitySource: String
        let measuredGrams: Double
        let measuredGramsMin: Double
        let measuredGramsMax: Double
        let notes: [String]
    }

    let mealName: String
    let items: [Item]

    init(mealName: String, measurements: [FoodMeasuredItem]) {
        self.mealName = mealName
        items = measurements.map { measured in
            let measurement = measured.measurement
            return Item(
                itemIndex: measured.detection.index,
                name: measured.detection.name,
                category: measured.detection.category.rawValue,
                containerType: measurement.containerType.rawValue,
                layeredOnIndex: measured.detection.layeredOnIndex,
                layeredOnName: measured.layeredOnName,
                volumeMl: Self.rounded(measurement.volumeMilliliters),
                volumeMinMl: Self.rounded(measurement.volumeMinMilliliters),
                volumeMaxMl: Self.rounded(measurement.volumeMaxMilliliters),
                footprintAreaCm2: Self.rounded(measurement.footprintAreaSquareCentimeters),
                meanHeightCm: Self.rounded(measurement.meanHeightCentimeters),
                coverage: Self.rounded(measurement.coverage, places: 2),
                densityGPerMl: Self.rounded(measurement.densityGramsPerMilliliter, places: 2),
                densitySource: measurement.densitySource.rawValue,
                measuredGrams: Self.rounded(measurement.measuredGrams),
                measuredGramsMin: Self.rounded(measurement.measuredGramsMin),
                measuredGramsMax: Self.rounded(measurement.measuredGramsMax),
                notes: measurement.notes
            )
        }
    }

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let string = String(data: try encoder.encode(self), encoding: .utf8) else {
            throw FoodAnalysisError.invalidResponse
        }
        return string
    }

    private static func rounded(_ value: Double, places: Int = 1) -> Double {
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }
}
