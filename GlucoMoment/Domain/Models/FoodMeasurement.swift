//
//  FoodMeasurement.swift
//  GlucoMoment
//

import Foundation

/// 份量数据的来源：纯照片估算，或 LiDAR 实测体积。
nonisolated enum FoodMeasurementMethod: String, Codable, Hashable, Sendable {
    case photoEstimate
    case lidarMeasured

    var label: String {
        switch self {
        case .photoEstimate:
            "照片估算"
        case .lidarMeasured:
            "LiDAR 实测"
        }
    }
}

/// 盛放食物的容器类型，决定体积计算时使用的内底形状。
nonisolated enum FoodContainerType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case flatPlate
    case shallowBowl
    case deepBowl
    case cup
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flatPlate:
            "平盘"
        case .shallowBowl:
            "浅碗"
        case .deepBowl:
            "深碗"
        case .cup:
            "杯"
        case .none:
            "无容器"
        }
    }

    var systemImage: String {
        switch self {
        case .flatPlate:
            "circle.dashed"
        case .shallowBowl:
            "circle.bottomhalf.filled"
        case .deepBowl:
            "smallcircle.filled.circle"
        case .cup:
            "cup.and.saucer"
        case .none:
            "square.dashed"
        }
    }
}

/// 食物大类，用于密度表未命中时的兜底以及提示词。
nonisolated enum FoodCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case staple
    case vegetable
    case meat
    case seafood
    case egg
    case soy
    case soup
    case beverage
    case fruit
    case snack
    case mixed
    case other
}

nonisolated enum FoodDensitySource: String, Codable, Hashable, Sendable {
    case localTable
    case model
    case categoryDefault

    var label: String {
        switch self {
        case .localTable:
            "本地密度表"
        case .model:
            "模型估计"
        case .categoryDefault:
            "类别默认值"
        }
    }
}

/// 单个食物的 LiDAR 测量摘要，随饮食记录持久化。
nonisolated struct FoodItemMeasurement: Hashable, Codable, Sendable {
    var method: FoodMeasurementMethod
    var volumeMilliliters: Double
    var volumeMinMilliliters: Double
    var volumeMaxMilliliters: Double
    var footprintAreaSquareCentimeters: Double
    var meanHeightCentimeters: Double
    /// 食物区域中被深度数据实际覆盖的比例（0...1）。
    var coverage: Double
    var containerType: FoodContainerType
    var densityGramsPerMilliliter: Double
    var densityMinGramsPerMilliliter: Double
    var densityMaxGramsPerMilliliter: Double
    var densitySource: FoodDensitySource
    var measuredGrams: Double
    var measuredGramsMin: Double
    var measuredGramsMax: Double
    var notes: [String]
}
