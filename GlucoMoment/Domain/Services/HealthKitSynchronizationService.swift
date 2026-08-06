//
//  HealthKitSynchronizationService.swift
//  GlucoMoment
//

import Foundation

struct HealthKitSynchronizationResult: Equatable, Sendable {
    let glucoseSampleCount: Int
    let mealCount: Int
    let synchronizedAt: Date
}

@MainActor
protocol HealthKitSynchronizing: AnyObject {
    var isHealthDataAvailable: Bool { get }

    func requestAuthorization() async throws
    func synchronize() async throws -> HealthKitSynchronizationResult
}

@MainActor
final class HealthKitSynchronizationService: HealthKitSynchronizing {
    private let healthKit: any HealthKitStoreClientProtocol
    private let glucoseRepository: HealthKitSynchronizedGlucoseRepository
    private let mealRepository: HealthKitSynchronizedMealRepository

    init(
        healthKit: any HealthKitStoreClientProtocol,
        glucoseRepository: HealthKitSynchronizedGlucoseRepository,
        mealRepository: HealthKitSynchronizedMealRepository
    ) {
        self.healthKit = healthKit
        self.glucoseRepository = glucoseRepository
        self.mealRepository = mealRepository
    }

    var isHealthDataAvailable: Bool {
        healthKit.isHealthDataAvailable
    }

    func requestAuthorization() async throws {
        try await healthKit.requestAuthorization()
    }

    func synchronize() async throws -> HealthKitSynchronizationResult {
        let glucoseCount = try await glucoseRepository.synchronize()
        let mealCount = try await mealRepository.synchronize()
        return HealthKitSynchronizationResult(
            glucoseSampleCount: glucoseCount,
            mealCount: mealCount,
            synchronizedAt: .now
        )
    }
}

@MainActor
final class UnavailableHealthKitSynchronizationService: HealthKitSynchronizing {
    let isHealthDataAvailable = false

    func requestAuthorization() async throws {
        throw HealthKitStoreError.healthDataUnavailable
    }

    func synchronize() async throws -> HealthKitSynchronizationResult {
        throw HealthKitStoreError.healthDataUnavailable
    }
}

enum HealthKitSynchronizationError: LocalizedError {
    case externalRecordIsReadOnly

    var errorDescription: String? {
        switch self {
        case .externalRecordIsReadOnly:
            "来自健康 App 的记录需要在原始来源中修改或删除。"
        }
    }
}
