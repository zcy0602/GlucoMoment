//
//  GlucoseTargetSettings.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 血糖目标范围设置：先选人群填入推荐值，再按医嘱自定义。保存在 UserDefaults，只在本机使用。
/// 读数状态（`GlucoseReading.state`）需要在任何地方拿到当前范围，所以用一个共享实例，
/// 通过 `GlucoseTargetRange.current` 读取
@MainActor
@Observable
final class GlucoseTargetSettings {
    static let shared = GlucoseTargetSettings()

    private enum Key {
        static let population = "GlucoMoment.GlucoseTarget.Population"
        static let lowerBound = "GlucoMoment.GlucoseTarget.LowerBound"
        static let upperBound = "GlucoMoment.GlucoseTarget.UpperBound"
        static let hintDismissed = "GlucoMoment.GlucoseTarget.HintDismissed"
    }

    /// nil 表示还没设置过，此时按 `GlucoseTargetRange.standard` 显示
    private(set) var population: GlucosePopulation?
    private(set) var range: GlucoseTargetRange
    /// 血糖页「设置你的目标范围」提示被关掉了
    var isHintDismissed: Bool {
        didSet { defaults?.set(isHintDismissed, forKey: Key.hintDismissed) }
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let population = defaults.string(forKey: Key.population).flatMap(GlucosePopulation.init(rawValue:))
        self.population = population
        let stored = GlucoseTargetRange(
            lowerBound: defaults.double(forKey: Key.lowerBound),
            upperBound: defaults.double(forKey: Key.upperBound)
        )
        // 没存过时 double(forKey:) 返回 0；存的值不在可选范围内时也退回推荐值
        range = stored.isSelectable ? stored : (population?.recommendedRange ?? .standard)
        isHintDismissed = defaults.bool(forKey: Key.hintDismissed)
    }

    /// 测试和 Preview 用，不读写 UserDefaults
    init(population: GlucosePopulation?, range: GlucoseTargetRange) {
        defaults = nil
        self.population = population
        self.range = range
        isHintDismissed = false
    }

    /// 是否设置过（选过人群或改过数值）
    var isConfigured: Bool { population != nil || range != .standard }

    /// 当前范围与所选人群的推荐值不同
    var isCustomized: Bool {
        guard let population else { return range != .standard }
        return range != population.recommendedRange
    }

    func save(population: GlucosePopulation?, range: GlucoseTargetRange) {
        let range = GlucoseTargetRange(
            lowerBound: GlucoseTargetRange.rounded(range.lowerBound),
            upperBound: GlucoseTargetRange.rounded(range.upperBound)
        )
        guard range.isSelectable else { return }
        self.population = population
        self.range = range
        defaults?.set(population?.rawValue, forKey: Key.population)
        defaults?.set(range.lowerBound, forKey: Key.lowerBound)
        defaults?.set(range.upperBound, forKey: Key.upperBound)
    }
}
