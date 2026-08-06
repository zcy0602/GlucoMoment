//
//  HealthKitSynchronizedGlucoseRepository.swift
//  GlucoMoment
//

import Foundation

@MainActor
final class HealthKitSynchronizedGlucoseRepository: GlucoseRepository {
    private let local: SwiftDataGlucoseRepository
    private let syncStates: HealthKitSyncStateRepository
    private let healthKit: any HealthKitStoreClientProtocol

    init(
        local: SwiftDataGlucoseRepository,
        syncStates: HealthKitSyncStateRepository,
        healthKit: any HealthKitStoreClientProtocol
    ) {
        self.local = local
        self.syncStates = syncStates
        self.healthKit = healthKit
    }

    func readings(in interval: DateInterval) throws -> [GlucoseReading] {
        let deletedIDs = try syncStates.pendingDeletionIDs(kind: .glucose)
        return try local.readings(in: interval).filter { !deletedIDs.contains($0.id) }
    }

    func latestReading() throws -> GlucoseReading? {
        let deletedIDs = try syncStates.pendingDeletionIDs(kind: .glucose)
        return try local.allReadings().last { !deletedIDs.contains($0.id) }
    }

    func save(_ reading: GlucoseReading) async throws {
        guard reading.source != .healthKit else {
            throw HealthKitSynchronizationError.externalRecordIsReadOnly
        }
        try local.save(reading)
        try syncStates.upsert(
            recordID: reading.id,
            kind: .glucose,
            status: .pendingUpload,
            externalIdentifier: reading.externalIdentifier
        )
        await uploadIfPossible(reading)
    }

    func delete(id: UUID) async throws {
        guard let reading = try local.reading(id: id) else { return }
        guard reading.source != .healthKit else {
            throw HealthKitSynchronizationError.externalRecordIsReadOnly
        }
        let state = try syncStates.state(recordID: id, kind: .glucose)
        guard state?.status == .synced || reading.externalIdentifier != nil else {
            try local.delete(id: id)
            try syncStates.delete(recordID: id, kind: .glucose)
            return
        }

        try syncStates.upsert(
            recordID: id,
            kind: .glucose,
            status: .pendingDeletion,
            externalIdentifier: state?.externalIdentifier ?? reading.externalIdentifier
        )
        await finishDeletionIfPossible(id: id)
    }

    func replaceHealthKitReadings(with readings: [GlucoseReading]) throws {
        try local.replaceHealthKitReadings(with: readings)
    }

    func synchronize() async throws -> Int {
        try await flushPendingDeletions()

        let localReadings = try local.readings(in: recentInterval)
            .filter { $0.source != .healthKit }
        let stateByID = Dictionary(
            uniqueKeysWithValues: try syncStates.states(kind: .glucose).map { ($0.recordID, $0) }
        )
        for reading in localReadings {
            let state = stateByID[reading.id]
            if state == nil || state?.status == .pendingUpload {
                await uploadIfPossible(reading)
            }
        }

        let snapshot = try await healthKit.glucoseSnapshot()
        let refreshedStates = try syncStates.states(kind: .glucose)
        for state in refreshedStates where state.status == .synced {
            guard localReadings.contains(where: { $0.id == state.recordID }) else { continue }
            if !snapshot.ownedLocalRecordIDs.contains(state.recordID) {
                try local.delete(id: state.recordID)
                try syncStates.delete(recordID: state.recordID, kind: .glucose)
            }
        }

        try local.replaceHealthKitReadings(with: snapshot.externalReadings)
        return snapshot.externalReadings.count + snapshot.ownedLocalRecordIDs.count
    }

    private func uploadIfPossible(_ reading: GlucoseReading) async {
        guard healthKit.isHealthDataAvailable else { return }
        do {
            let externalIdentifier = try await healthKit.saveGlucose(reading)
            var synchronizedReading = reading
            synchronizedReading.externalIdentifier = externalIdentifier
            try local.save(synchronizedReading)
            try syncStates.upsert(
                recordID: reading.id,
                kind: .glucose,
                status: .synced,
                externalIdentifier: externalIdentifier
            )
        } catch {
            // 保留 pendingUpload；授权恢复或下次同步时自动重试。
        }
    }

    private func finishDeletionIfPossible(id: UUID) async {
        guard healthKit.isHealthDataAvailable else { return }
        do {
            try await healthKit.deleteGlucose(localRecordID: id)
            try local.delete(id: id)
            try syncStates.delete(recordID: id, kind: .glucose)
        } catch {
            // 保留隐藏的 pendingDeletion 墓碑，避免删除失败时记录重新出现。
        }
    }

    private func flushPendingDeletions() async throws {
        let states = try syncStates.states(kind: .glucose)
        for state in states where state.status == .pendingDeletion {
            await finishDeletionIfPossible(id: state.recordID)
        }
    }

    private var recentInterval: DateInterval {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return DateInterval(start: start, end: .distantFuture)
    }
}
