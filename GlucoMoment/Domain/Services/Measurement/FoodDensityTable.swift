//
//  FoodDensityTable.swift
//  GlucoMoment
//

import Foundation

/// 堆积密度区间（g/ml）。LiDAR 测得的是包含空隙的外形体积，因此这里使用「盛装状态」下的
/// 表观密度，而不是食材本身的真实密度（例如米饭约 0.8、叶菜约 0.45）。
nonisolated struct FoodDensityEstimate: Sendable, Hashable {
    var minimum: Double
    var maximum: Double
    var source: FoodDensitySource

    init(minimum: Double, maximum: Double, source: FoodDensitySource) {
        let lower = min(minimum, maximum)
        let upper = max(minimum, maximum)
        self.minimum = lower.clamped(to: FoodDensityTable.plausibleRange)
        self.maximum = upper.clamped(to: FoodDensityTable.plausibleRange)
        self.source = source
    }

    var nominal: Double { (minimum + maximum) / 2 }
}

nonisolated enum FoodDensityTable {
    /// 合理的密度范围，用于约束模型返回值。
    static let plausibleRange: ClosedRange<Double> = 0.1...1.5

    struct Entry: Sendable, Hashable {
        let aliases: [String]
        let minimum: Double
        let maximum: Double
    }

    /// 常见中式餐食。匹配时优先选择最长的别名，例如「番茄炒蛋」优先于「炒蛋」。
    static let entries: [Entry] = [
        Entry(aliases: ["米饭", "白饭", "白米饭", "糙米饭", "杂粮饭", "饭"], minimum: 0.75, maximum: 0.9),
        Entry(aliases: ["炒饭", "蛋炒饭", "扬州炒饭"], minimum: 0.6, maximum: 0.8),
        Entry(aliases: ["粥", "稀饭", "小米粥", "白粥"], minimum: 0.95, maximum: 1.05),
        Entry(aliases: ["面条", "拉面", "汤面", "拌面", "炒面", "米粉", "米线", "河粉", "意面"], minimum: 0.55, maximum: 0.85),
        Entry(aliases: ["馒头", "花卷"], minimum: 0.3, maximum: 0.45),
        Entry(aliases: ["包子", "肉包", "菜包"], minimum: 0.5, maximum: 0.7),
        Entry(aliases: ["饺子", "水饺", "馄饨", "云吞", "锅贴"], minimum: 0.7, maximum: 0.95),
        Entry(aliases: ["面包", "吐司"], minimum: 0.2, maximum: 0.35),
        Entry(aliases: ["饼", "煎饼", "烙饼", "葱油饼"], minimum: 0.5, maximum: 0.75),
        Entry(aliases: ["土豆泥"], minimum: 0.95, maximum: 1.1),
        Entry(aliases: ["土豆", "土豆丝", "薯条"], minimum: 0.5, maximum: 0.8),
        Entry(aliases: ["红薯", "紫薯", "山药", "芋头"], minimum: 0.65, maximum: 0.9),
        Entry(aliases: ["玉米"], minimum: 0.6, maximum: 0.8),
        Entry(aliases: ["青菜", "炒青菜", "白菜", "菠菜", "生菜", "油麦菜", "空心菜", "小白菜", "叶菜"], minimum: 0.35, maximum: 0.6),
        Entry(aliases: ["西兰花", "花菜", "菜花"], minimum: 0.3, maximum: 0.5),
        Entry(aliases: ["沙拉", "蔬菜沙拉"], minimum: 0.2, maximum: 0.4),
        Entry(aliases: ["茄子", "鱼香茄子", "红烧茄子"], minimum: 0.7, maximum: 0.95),
        Entry(aliases: ["番茄炒蛋", "西红柿炒鸡蛋", "西红柿炒蛋"], minimum: 0.75, maximum: 0.95),
        Entry(aliases: ["炒蛋", "炒鸡蛋", "鸡蛋", "煎蛋", "蒸蛋", "鸡蛋羹"], minimum: 0.5, maximum: 0.8),
        Entry(aliases: ["豆腐", "麻婆豆腐", "家常豆腐"], minimum: 0.9, maximum: 1.05),
        Entry(aliases: ["红烧肉", "东坡肉", "回锅肉", "梅菜扣肉"], minimum: 0.75, maximum: 1.0),
        Entry(aliases: ["鸡胸", "鸡胸肉", "牛排", "猪排"], minimum: 0.85, maximum: 1.05),
        Entry(aliases: ["鸡块", "鸡腿", "鸡翅", "排骨", "宫保鸡丁", "辣子鸡"], minimum: 0.6, maximum: 0.9),
        Entry(aliases: ["牛肉", "猪肉", "肉片", "肉丝", "肉末", "炒肉"], minimum: 0.65, maximum: 0.95),
        Entry(aliases: ["鱼", "鱼肉", "清蒸鱼", "红烧鱼"], minimum: 0.8, maximum: 1.0),
        Entry(aliases: ["虾", "虾仁"], minimum: 0.6, maximum: 0.85),
        Entry(aliases: ["汤", "鸡汤", "排骨汤", "紫菜汤", "蛋花汤", "例汤"], minimum: 0.98, maximum: 1.03),
        Entry(aliases: ["牛奶", "奶"], minimum: 1.02, maximum: 1.04),
        Entry(aliases: ["豆浆"], minimum: 1.0, maximum: 1.03),
        Entry(aliases: ["酸奶"], minimum: 1.03, maximum: 1.1),
        Entry(aliases: ["果汁", "饮料", "可乐", "茶", "咖啡"], minimum: 1.0, maximum: 1.05),
        Entry(aliases: ["西瓜", "哈密瓜"], minimum: 0.6, maximum: 0.8),
        Entry(aliases: ["苹果", "梨", "橙子", "水果", "水果拼盘", "葡萄", "草莓"], minimum: 0.55, maximum: 0.8),
        Entry(aliases: ["香蕉"], minimum: 0.7, maximum: 0.9),
        Entry(aliases: ["坚果", "花生"], minimum: 0.5, maximum: 0.7)
    ]

    /// 按别名包含关系匹配；多条命中时取最长别名。
    static func entry(matching name: String) -> Entry? {
        let normalized = name
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var best: (entry: Entry, length: Int)?
        for entry in entries {
            for alias in entry.aliases where normalized.contains(alias) {
                if alias.count > (best?.length ?? 0) {
                    best = (entry, alias.count)
                }
            }
        }
        return best?.entry
    }

    static func categoryDefault(for category: FoodCategory) -> FoodDensityEstimate {
        let range: ClosedRange<Double> = switch category {
        case .staple:
            0.55...0.9
        case .vegetable:
            0.35...0.7
        case .meat:
            0.65...0.95
        case .seafood:
            0.65...0.95
        case .egg:
            0.5...0.85
        case .soy:
            0.85...1.05
        case .soup, .beverage:
            0.98...1.05
        case .fruit:
            0.55...0.85
        case .snack:
            0.3...0.7
        case .mixed, .other:
            0.5...0.95
        }
        return FoodDensityEstimate(minimum: range.lowerBound, maximum: range.upperBound, source: .categoryDefault)
    }

    /// 本地表优先；未命中时用模型返回的区间；两者都没有时用类别默认值。
    static func resolve(
        name: String,
        category: FoodCategory?,
        modelRange: ClosedRange<Double>?
    ) -> FoodDensityEstimate {
        if let entry = entry(matching: name) {
            return FoodDensityEstimate(minimum: entry.minimum, maximum: entry.maximum, source: .localTable)
        }
        if let modelRange, modelRange.lowerBound > 0 {
            return FoodDensityEstimate(minimum: modelRange.lowerBound, maximum: modelRange.upperBound, source: .model)
        }
        return categoryDefault(for: category ?? .other)
    }
}

nonisolated enum FoodMeasurementBuilder {
    /// 组合体积与密度得到克重区间：下限 = 最小体积 × 最小密度，上限 = 最大体积 × 最大密度。
    static func makeMeasurement(
        volume: FoodVolumeResult,
        containerType: FoodContainerType,
        density: FoodDensityEstimate
    ) -> FoodItemMeasurement {
        FoodItemMeasurement(
            method: .lidarMeasured,
            volumeMilliliters: volume.volumeMilliliters,
            volumeMinMilliliters: volume.volumeMinMilliliters,
            volumeMaxMilliliters: volume.volumeMaxMilliliters,
            footprintAreaSquareCentimeters: volume.footprintAreaSquareCentimeters,
            meanHeightCentimeters: volume.meanHeightCentimeters,
            coverage: volume.coverage,
            containerType: containerType,
            densityGramsPerMilliliter: density.nominal,
            densityMinGramsPerMilliliter: density.minimum,
            densityMaxGramsPerMilliliter: density.maximum,
            densitySource: density.source,
            measuredGrams: volume.volumeMilliliters * density.nominal,
            measuredGramsMin: volume.volumeMinMilliliters * density.minimum,
            measuredGramsMax: volume.volumeMaxMilliliters * density.maximum,
            notes: volume.notes.map(\.message)
        )
    }
}
