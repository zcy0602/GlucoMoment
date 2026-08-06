//
//  HealthKitSynchronizedMealRepository.swift
//  GlucoMoment
//

import Foundation

@MainActor
final class HealthKitSynchronizedMealRepository: MealRepository {
    private let local: SwiftDataMealRepository
    private let syncStates: HealthKitSyncStateRepository
    private let healthKit: any HealthKitStoreClientProtocol

    init(
        local: SwiftDataMealRepository,
        syncStates: HealthKitSyncStateRepository,
        healthKit: any HealthKitStoreClientProtocol
    ) {
        self.local = local
        self.syncStates = syncStates
        self.healthKit = healthKit
    }

    func meals(in interval: DateInterval, period: MealPeriod?) throws -> [MealRecord] {
        let deletedIDs = try syncStates.pendingDeletionIDs(kind: .meal)
        return try local.meals(in: interval, period: period)
            .filter { !deletedIDs.contains($0.id) }
    }

    func save(_ meal: MealRecord) async throws {
        guard meal.source != .healthKit else {
            throw HealthKitSynchronizationError.externalRecordIsReadOnly
        }
        try local.save(meal)
        try syncStates.upsert(
            recordID: meal.id,
            kind: .meal,
            status: .pendingUpload,
            nutritionAvailabilityRawValue: meal.nutritionAvailability.rawValue
        )
        await uploadIfPossible(meal)
    }

    func delete(id: UUID) async throws {
        guard let meal = try local.meal(id: id) else { return }
        guard meal.source != .healthKit else {
            throw HealthKitSynchronizationError.externalRecordIsReadOnly
        }
        let state = try syncStates.state(recordID: id, kind: .meal)
        guard state?.status == .synced else {
            try local.delete(id: id)
            try syncStates.delete(recordID: id, kind: .meal)
            return
        }

        try syncStates.upsert(
            recordID: id,
            kind: .meal,
            status: .pendingDeletion,
            externalIdentifier: state?.externalIdentifier,
            nutritionAvailabilityRawValue: meal.nutritionAvailability.rawValue
        )
        await finishDeletionIfPossible(id: id)
    }

    func synchronize() async throws -> Int {
        try await flushPendingDeletions()

        let localMeals = try local.meals(in: recentInterval, period: nil)
            .filter { $0.source != .healthKit }
        let stateByID = Dictionary(
            uniqueKeysWithValues: try syncStates.states(kind: .meal).map { ($0.recordID, $0) }
        )
        for meal in localMeals {
            let state = stateByID[meal.id]
            if state == nil || state?.status == .pendingUpload {
                await uploadIfPossible(meal)
            }
        }

        let snapshot = try await healthKit.mealSnapshot()
        let refreshedStates = try syncStates.states(kind: .meal)
        for state in refreshedStates where state.status == .synced {
            guard localMeals.contains(where: { $0.id == state.recordID }) else { continue }
            if !snapshot.ownedLocalRecordIDs.contains(state.recordID) {
                try local.delete(id: state.recordID)
                try syncStates.delete(recordID: state.recordID, kind: .meal)
            }
        }

        try local.replaceHealthKitMeals(with: snapshot.externalMeals)
        return snapshot.externalMeals.count + snapshot.ownedLocalRecordIDs.count
    }

    private func uploadIfPossible(_ meal: MealRecord) async {
        guard healthKit.isHealthDataAvailable else { return }
        do {
            let externalIdentifier = try await healthKit.saveMeal(meal)
            try syncStates.upsert(
                recordID: meal.id,
                kind: .meal,
                status: .synced,
                externalIdentifier: externalIdentifier,
                nutritionAvailabilityRawValue: meal.nutritionAvailability.rawValue
            )
        } catch {
            // 保留 pendingUpload；授权恢复或下次同步时自动重试。
        }
    }

    private func finishDeletionIfPossible(id: UUID) async {
        guard healthKit.isHealthDataAvailable else { return }
        do {
            try await healthKit.deleteMeal(localRecordID: id)
            try local.delete(id: id)
            try syncStates.delete(recordID: id, kind: .meal)
        } catch {
            // 保留隐藏的 pendingDeletion 墓碑，避免删除失败时记录重新出现。
        }
    }

    private func flushPendingDeletions() async throws {
        let states = try syncStates.states(kind: .meal)
        for state in states where state.status == .pendingDeletion {
            await finishDeletionIfPossible(id: state.recordID)
        }
    }

    private var recentInterval: DateInterval {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return DateInterval(start: start, end: .distantFuture)
    }
}
