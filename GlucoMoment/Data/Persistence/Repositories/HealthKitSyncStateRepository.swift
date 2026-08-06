//
//  HealthKitSyncStateRepository.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@MainActor
final class HealthKitSyncStateRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = modelContainer.mainContext
    }

    func state(recordID: UUID, kind: HealthKitRecordKind) throws -> HealthKitSyncState? {
        try entity(recordID: recordID, kind: kind).map(makeState)
    }

    func states(kind: HealthKitRecordKind) throws -> [HealthKitSyncState] {
        let kindRawValue = kind.rawValue
        let predicate = #Predicate<HealthKitSyncStateEntity> {
            $0.recordKindRawValue == kindRawValue
        }
        return try modelContext.fetch(
            FetchDescriptor<HealthKitSyncStateEntity>(predicate: predicate)
        ).map(makeState)
    }

    func pendingDeletionIDs(kind: HealthKitRecordKind) throws -> Set<UUID> {
        Set(
            try states(kind: kind)
                .filter { $0.status == .pendingDeletion }
                .map(\.recordID)
        )
    }

    func upsert(
        recordID: UUID,
        kind: HealthKitRecordKind,
        status: HealthKitSyncStatus,
        externalIdentifier: String? = nil,
        nutritionAvailabilityRawValue: Int? = nil
    ) throws {
        if let entity = try entity(recordID: recordID, kind: kind) {
            entity.syncStatusRawValue = status.rawValue
            entity.externalIdentifier = externalIdentifier ?? entity.externalIdentifier
            entity.nutritionAvailabilityRawValue =
                nutritionAvailabilityRawValue ?? entity.nutritionAvailabilityRawValue
            entity.updatedAt = .now
        } else {
            modelContext.insert(
                HealthKitSyncStateEntity(
                    recordID: recordID,
                    recordKindRawValue: kind.rawValue,
                    syncStatusRawValue: status.rawValue,
                    externalIdentifier: externalIdentifier,
                    nutritionAvailabilityRawValue: nutritionAvailabilityRawValue,
                    updatedAt: .now
                )
            )
        }
        try modelContext.save()
    }

    func delete(recordID: UUID, kind: HealthKitRecordKind) throws {
        guard let entity = try entity(recordID: recordID, kind: kind) else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    private func entity(
        recordID: UUID,
        kind: HealthKitRecordKind
    ) throws -> HealthKitSyncStateEntity? {
        let kindRawValue = kind.rawValue
        let predicate = #Predicate<HealthKitSyncStateEntity> {
            $0.recordID == recordID && $0.recordKindRawValue == kindRawValue
        }
        var descriptor = FetchDescriptor<HealthKitSyncStateEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func makeState(from entity: HealthKitSyncStateEntity) -> HealthKitSyncState {
        HealthKitSyncState(
            recordID: entity.recordID,
            kind: HealthKitRecordKind(rawValue: entity.recordKindRawValue) ?? .glucose,
            status: HealthKitSyncStatus(rawValue: entity.syncStatusRawValue) ?? .pendingUpload,
            externalIdentifier: entity.externalIdentifier,
            nutritionAvailabilityRawValue: entity.nutritionAvailabilityRawValue
        )
    }
}
