//
//  GlucoseTargetSettingsTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@MainActor
@Suite("血糖目标范围设置")
struct GlucoseTargetSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "GlucoseTargetSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("未设置时按糖尿病成人的推荐范围")
    func defaultsToStandard() {
        let settings = GlucoseTargetSettings(defaults: makeDefaults())
        #expect(settings.range == .standard)
        #expect(settings.population == nil)
        #expect(!settings.isConfigured)
        #expect(!settings.isCustomized)
    }

    @Test(
        "各人群的推荐值",
        arguments: [
            (GlucosePopulation.type1, 3.9, 10.0),
            (.type2, 3.9, 10.0),
            (.pregnancy, 3.5, 7.8),
            (.otherDiabetes, 3.9, 10.0),
            (.prediabetes, 3.9, 7.8),
            (.noDiabetes, 3.9, 7.8),
            (.other, 3.9, 10.0)
        ]
    )
    func recommendedRanges(population: GlucosePopulation, lower: Double, upper: Double) {
        #expect(population.recommendedRange == GlucoseTargetRange(lowerBound: lower, upperBound: upper))
        #expect(population.recommendedRange.isSelectable)
    }

    @Test("保存后重新读取，并能区分推荐值和自定义")
    func persistsAndDetectsCustomization() {
        let defaults = makeDefaults()
        let settings = GlucoseTargetSettings(defaults: defaults)
        settings.save(population: .noDiabetes, range: GlucoseTargetRange.tight)
        #expect(!settings.isCustomized)

        settings.save(population: .noDiabetes, range: GlucoseTargetRange(lowerBound: 4.0, upperBound: 8.5))
        let reloaded = GlucoseTargetSettings(defaults: defaults)
        #expect(reloaded.population == .noDiabetes)
        #expect(reloaded.range == GlucoseTargetRange(lowerBound: 4.0, upperBound: 8.5))
        #expect(reloaded.isConfigured)
        #expect(reloaded.isCustomized)
    }

    @Test("超出可选范围的值不保存，读到无效值时退回推荐值")
    func rejectsOutOfRangeValues() {
        let defaults = makeDefaults()
        let settings = GlucoseTargetSettings(defaults: defaults)
        settings.save(population: .type2, range: GlucoseTargetRange(lowerBound: 2.0, upperBound: 20.0))
        #expect(settings.range == .standard)
        #expect(settings.population == nil)

        defaults.set(GlucosePopulation.pregnancy.rawValue, forKey: "GlucoMoment.GlucoseTarget.Population")
        defaults.set(9.0, forKey: "GlucoMoment.GlucoseTarget.LowerBound")
        defaults.set(7.0, forKey: "GlucoMoment.GlucoseTarget.UpperBound")
        #expect(GlucoseTargetSettings(defaults: defaults).range == .pregnancy)
    }

    @Test("自定义范围改变读数状态，低血糖安全线不变")
    func customRangeChangesStateOnly() {
        let tight = GlucoseTargetRange.tight
        #expect(tight.state(for: 8.5) == .elevated)
        #expect(GlucoseTargetRange.standard.state(for: 8.5) == .inRange)
        #expect(MealGlucoseResponseCalculator.lowThreshold == 3.9)
    }
}
