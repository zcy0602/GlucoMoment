//
//  HealthKitStoreClient.swift
//  GlucoMoment
//

import Foundation
import HealthKit

struct HealthKitGlucoseSnapshot: Sendable {
    let externalReadings: [GlucoseReading]
    let ownedLocalRecordIDs: Set<UUID>
    /// 这次查询覆盖的起点。对账只处理这之后的记录，更早的已同步数据留在本地，历史会逐渐积累
    var coveredStart: Date = .distantPast
}

struct HealthKitMealImport: Sendable {
    let meal: MealRecord
    let externalIdentifier: String
}

struct HealthKitMealSnapshot: Sendable {
    let externalMeals: [HealthKitMealImport]
    let ownedLocalRecordIDs: Set<UUID>
    /// 这次查询覆盖的起点，含义同 HealthKitGlucoseSnapshot.coveredStart
    var coveredStart: Date = .distantPast
}

@MainActor
protocol HealthKitStoreClientProtocol: AnyObject {
    var isHealthDataAvailable: Bool { get }

    func requestAuthorization() async throws
    func glucoseSnapshot() async throws -> HealthKitGlucoseSnapshot
    func mealSnapshot() async throws -> HealthKitMealSnapshot
    func saveGlucose(_ reading: GlucoseReading) async throws -> String
    func saveMeal(_ meal: MealRecord) async throws -> String
    func deleteGlucose(localRecordID: UUID) async throws
    func deleteMeal(localRecordID: UUID) async throws
}

@MainActor
final class HealthKitStoreClient: HealthKitStoreClientProtocol {
    private enum Nutrient: CaseIterable {
        case energy
        case carbohydrates
        case protein
        case fat
        case fiber

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .energy: .dietaryEnergyConsumed
            case .carbohydrates: .dietaryCarbohydrates
            case .protein: .dietaryProtein
            case .fat: .dietaryFatTotal
            case .fiber: .dietaryFiber
            }
        }

        var unit: HKUnit {
            self == .energy ? .kilocalorie() : .gram()
        }

        var availability: MealNutritionAvailability {
            switch self {
            case .energy: .energy
            case .carbohydrates: .carbohydrates
            case .protein: .protein
            case .fat: .fat
            case .fiber: .fiber
            }
        }
    }

    private let healthStore: HKHealthStore
    private let historyDayCount: Int
    private let bundleIdentifier: String

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        historyDayCount: Int = 30,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "GlucoMoment"
    ) {
        self.healthStore = healthStore
        self.historyDayCount = historyDayCount
        self.bundleIdentifier = bundleIdentifier
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitStoreError.healthDataUnavailable
        }
        let types = try allQuantityTypes()
        try await healthStore.requestAuthorization(
            toShare: Set(types),
            read: Set(types)
        )
    }

    func glucoseSnapshot() async throws -> HealthKitGlucoseSnapshot {
        let type = try quantityType(.bloodGlucose)
        let start = recentSamplesStart
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: recentSamplesPredicate(since: start))],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)]
        )
        let samples = try await descriptor.result(for: healthStore)
        var externalReadings: [GlucoseReading] = []
        var ownedLocalRecordIDs: Set<UUID> = []

        for sample in samples {
            if let localID = ownedLocalRecordID(from: sample) {
                ownedLocalRecordIDs.insert(localID)
            } else {
                externalReadings.append(Self.makeReading(from: sample))
            }
        }

        return HealthKitGlucoseSnapshot(
            externalReadings: externalReadings,
            ownedLocalRecordIDs: ownedLocalRecordIDs,
            coveredStart: start
        )
    }

    func mealSnapshot() async throws -> HealthKitMealSnapshot {
        let type = try foodCorrelationType()
        let start = recentSamplesStart
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: type, predicate: recentSamplesPredicate(since: start))],
            sortDescriptors: [SortDescriptor(\HKCorrelation.startDate)]
        )
        let correlations = try await descriptor.result(for: healthStore)
        var externalMeals: [HealthKitMealImport] = []
        var ownedLocalRecordIDs: Set<UUID> = []

        for correlation in correlations {
            if let localID = ownedLocalRecordID(from: correlation) {
                ownedLocalRecordIDs.insert(localID)
            } else {
                externalMeals.append(try makeMealImport(from: correlation))
            }
        }

        return HealthKitMealSnapshot(
            externalMeals: externalMeals,
            ownedLocalRecordIDs: ownedLocalRecordIDs,
            coveredStart: start
        )
    }

    func saveGlucose(_ reading: GlucoseReading) async throws -> String {
        try await deleteGlucose(localRecordID: reading.id)
        let sample = try Self.makeGlucoseSample(from: reading)
        try await save(sample)
        return sample.uuid.uuidString
    }

    func saveMeal(_ meal: MealRecord) async throws -> String {
        try await deleteMeal(localRecordID: meal.id)
        let correlation = try makeFoodCorrelation(from: meal)
        try await save(correlation)
        return correlation.uuid.uuidString
    }

    func deleteGlucose(localRecordID: UUID) async throws {
        let type = try quantityType(.bloodGlucose)
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [localRecordID.uuidString]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: []
        )
        try await delete(try await descriptor.result(for: healthStore))
    }

    func deleteMeal(localRecordID: UUID) async throws {
        let type = try foodCorrelationType()
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [localRecordID.uuidString]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: type, predicate: predicate)],
            sortDescriptors: []
        )
        let correlations = try await descriptor.result(for: healthStore)
        let objects = correlations.flatMap { correlation in
            [correlation as HKObject] + correlation.objects.map { $0 as HKObject }
        }
        try await delete(objects)
    }

    static func makeReading(from sample: HKQuantitySample) -> GlucoseReading {
        GlucoseReading(
            id: sample.uuid,
            measuredAt: sample.startDate,
            value: sample.quantity.doubleValue(for: bloodGlucoseUnit),
            source: .healthKit,
            externalIdentifier: sample.uuid.uuidString
        )
    }

    static func makeGlucoseSample(from reading: GlucoseReading) throws -> HKQuantitySample {
        guard let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw HealthKitStoreError.dataTypeUnavailable
        }
        return HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: bloodGlucoseUnit, doubleValue: reading.value),
            start: reading.measuredAt,
            end: reading.measuredAt,
            metadata: [
                HKMetadataKeyExternalUUID: reading.id.uuidString,
                HKMetadataKeyWasUserEntered: true
            ]
        )
    }

    private var recentSamplesStart: Date {
        Calendar.current.date(
            byAdding: .day,
            value: -historyDayCount,
            to: .now
        ) ?? .distantPast
    }

    private func recentSamplesPredicate(since start: Date) -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: start,
            end: nil,
            options: .strictStartDate
        )
    }

    private func makeMealImport(from correlation: HKCorrelation) throws -> HealthKitMealImport {
        var availability: MealNutritionAvailability = []
        var values: [Nutrient: Double] = [:]

        for nutrient in Nutrient.allCases {
            let type = try quantityType(nutrient.identifier)
            let samples = correlation.objects(for: type).compactMap { $0 as? HKQuantitySample }
            guard !samples.isEmpty else {
                continue
            }
            values[nutrient] = samples.reduce(0) {
                $0 + $1.quantity.doubleValue(for: nutrient.unit)
            }
            availability.insert(nutrient.availability)
        }

        let title = correlation.metadata?[HKMetadataKeyFoodType] as? String
            ?? "健康 App 餐食"
        let meal = MealRecord(
            id: correlation.uuid,
            eatenAt: correlation.startDate,
            mealPeriod: MealPeriod.inferred(for: correlation.startDate),
            title: title,
            source: .healthKit,
            note: "从健康 App 同步；餐次根据记录时间推断。",
            caloriesKcal: values[.energy] ?? 0,
            carbohydratesGrams: values[.carbohydrates] ?? 0,
            proteinGrams: values[.protein] ?? 0,
            fatGrams: values[.fat] ?? 0,
            fiberGrams: values[.fiber] ?? 0,
            items: [],
            nutritionAvailability: availability
        )
        return HealthKitMealImport(
            meal: meal,
            externalIdentifier: correlation.uuid.uuidString
        )
    }

    private func makeFoodCorrelation(from meal: MealRecord) throws -> HKCorrelation {
        let type = try foodCorrelationType()
        var samples: Set<HKSample> = []

        for nutrient in Nutrient.allCases {
            let value: Double
            switch nutrient {
            case .energy: value = meal.caloriesKcal
            case .carbohydrates: value = meal.carbohydratesGrams
            case .protein: value = meal.proteinGrams
            case .fat: value = meal.fatGrams
            case .fiber: value = meal.fiberGrams
            }
            let sample = HKQuantitySample(
                type: try quantityType(nutrient.identifier),
                quantity: HKQuantity(unit: nutrient.unit, doubleValue: value),
                start: meal.eatenAt,
                end: meal.eatenAt
            )
            samples.insert(sample)
        }

        return HKCorrelation(
            type: type,
            start: meal.eatenAt,
            end: meal.eatenAt,
            objects: samples,
            metadata: [
                HKMetadataKeyFoodType: meal.title,
                HKMetadataKeyExternalUUID: meal.id.uuidString,
                HKMetadataKeyWasUserEntered: true
            ]
        )
    }

    private func ownedLocalRecordID(from sample: HKSample) -> UUID? {
        guard sample.sourceRevision.source.bundleIdentifier == bundleIdentifier,
              let value = sample.metadata?[HKMetadataKeyExternalUUID] as? String else {
            return nil
        }
        return UUID(uuidString: value)
    }

    private func allQuantityTypes() throws -> [HKQuantityType] {
        try [quantityType(.bloodGlucose)]
            + Nutrient.allCases.map { try quantityType($0.identifier) }
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthKitStoreError.dataTypeUnavailable
        }
        return type
    }

    private func foodCorrelationType() throws -> HKCorrelationType {
        guard let type = HKObjectType.correlationType(forIdentifier: .food) else {
            throw HealthKitStoreError.dataTypeUnavailable
        }
        return type
    }

    private func save(_ object: HKObject) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            healthStore.save(object) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitStoreError.saveFailed)
                }
            }
        }
    }

    private func delete(_ objects: [HKObject]) async throws {
        guard !objects.isEmpty else { return }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            healthStore.delete(objects) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitStoreError.deleteFailed)
                }
            }
        }
    }

    private static let bloodGlucoseUnit = HKUnit
        .moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose)
        .unitDivided(by: .liter())
}

@MainActor
final class UnavailableHealthKitStoreClient: HealthKitStoreClientProtocol {
    let isHealthDataAvailable = false

    func requestAuthorization() async throws { throw HealthKitStoreError.healthDataUnavailable }
    func glucoseSnapshot() async throws -> HealthKitGlucoseSnapshot { throw HealthKitStoreError.healthDataUnavailable }
    func mealSnapshot() async throws -> HealthKitMealSnapshot { throw HealthKitStoreError.healthDataUnavailable }
    func saveGlucose(_ reading: GlucoseReading) async throws -> String { throw HealthKitStoreError.healthDataUnavailable }
    func saveMeal(_ meal: MealRecord) async throws -> String { throw HealthKitStoreError.healthDataUnavailable }
    func deleteGlucose(localRecordID: UUID) async throws { throw HealthKitStoreError.healthDataUnavailable }
    func deleteMeal(localRecordID: UUID) async throws { throw HealthKitStoreError.healthDataUnavailable }
}

enum HealthKitStoreError: LocalizedError {
    case healthDataUnavailable
    case dataTypeUnavailable
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable: "此设备目前无法使用健康数据。"
        case .dataTypeUnavailable: "系统未提供所需的健康数据类型。"
        case .saveFailed: "健康 App 未能保存记录。"
        case .deleteFailed: "健康 App 未能删除记录。"
        }
    }
}
