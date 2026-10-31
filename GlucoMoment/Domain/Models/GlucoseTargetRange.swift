//
//  GlucoseTargetRange.swift
//  GlucoMoment
//

/// 血糖目标范围，用于图表的目标带、读数状态和「目标范围内」的比例。
/// 用户可在设置里按人群选推荐值或自定义，当前值见 `current`
nonisolated struct GlucoseTargetRange: Hashable, Sendable {
    /// 糖尿病成人的推荐范围（国际 TIR 共识 2019），也是未设置时的默认值
    static let standard = GlucoseTargetRange(lowerBound: 3.9, upperBound: 10.0)
    /// 糖尿病前期和无糖尿病人群的严格范围（TITR）
    static let tight = GlucoseTargetRange(lowerBound: 3.9, upperBound: 7.8)
    /// 妊娠期的推荐范围（国际 TIR 共识 2019）
    static let pregnancy = GlucoseTargetRange(lowerBound: 3.5, upperBound: 7.8)

    /// 低血糖安全线，固定不变，不跟随用户设置的下限（ADA 1 级低血糖）。
    /// 复盘排除低血糖餐、安全提醒都用它
    static let hypoglycemiaThreshold = 3.9

    /// 可选的下限和上限，步长 0.1。两段不重叠，上限总比下限高 1 以上
    static let lowerBoundOptions: [Double] = stride(from: 30, through: 56, by: 1).map { Double($0) / 10 }
    static let upperBoundOptions: [Double] = stride(from: 67, through: 139, by: 1).map { Double($0) / 10 }

    /// 当前生效的目标范围。在 SwiftUI 的 body 里读取时会随设置变化自动刷新
    @MainActor
    static var current: GlucoseTargetRange {
        GlucoseTargetSettings.shared.range
    }

    let lowerBound: Double
    let upperBound: Double

    /// 两端都在可选范围内（按 0.1 取整后比较）
    var isSelectable: Bool {
        Self.lowerBoundOptions.contains(Self.rounded(lowerBound))
            && Self.upperBoundOptions.contains(Self.rounded(upperBound))
    }

    func state(for value: Double) -> GlucoseState {
        if value < lowerBound {
            .low
        } else if value > upperBound {
            .elevated
        } else {
            .inRange
        }
    }

    func contains(_ value: Double) -> Bool {
        lowerBound...upperBound ~= value
    }

    static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// 设置目标范围时选择的人群，只用来填推荐值，只保存在本机，不发给模型
nonisolated enum GlucosePopulation: String, CaseIterable, Identifiable, Sendable {
    case type1
    case type2
    case pregnancy
    case otherDiabetes
    case prediabetes
    case noDiabetes
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type1: "1 型糖尿病"
        case .type2: "2 型糖尿病"
        case .pregnancy: "妊娠期糖尿病 / 糖尿病合并妊娠"
        case .otherDiabetes: "特殊类型糖尿病"
        case .prediabetes: "糖尿病前期"
        case .noDiabetes: "无糖尿病"
        case .other: "其他 / 不确定"
        }
    }

    var recommendedRange: GlucoseTargetRange {
        switch self {
        case .type1, .type2, .otherDiabetes, .other: .standard
        case .pregnancy: .pregnancy
        case .prediabetes, .noDiabetes: .tight
        }
    }

    /// 推荐值的出处
    var recommendationSource: String {
        switch self {
        case .type1, .type2:
            "国际 TIR 共识（2019）对 1 型、2 型糖尿病成人的推荐"
        case .pregnancy:
            "国际 TIR 共识（2019）对妊娠期的推荐"
        case .otherDiabetes, .other:
            "暂无单独标准，按国际 TIR 共识（2019）对糖尿病成人的推荐"
        case .prediabetes, .noDiabetes:
            "严格目标范围（TITR），健康人群的连续血糖大多在这个范围内"
        }
    }
}
