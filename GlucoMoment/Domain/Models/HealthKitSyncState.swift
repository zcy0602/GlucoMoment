//
//  HealthKitSyncState.swift
//  GlucoMoment
//

import Foundation

enum HealthKitRecordKind: String, Codable, Sendable {
    case glucose
    case meal
}

enum HealthKitSyncStatus: String, Codable, Sendable {
    case pendingUpload
    case synced
    case pendingDeletion
    case external
}

struct HealthKitSyncState: Sendable {
    let recordID: UUID
    let kind: HealthKitRecordKind
    let status: HealthKitSyncStatus
    let externalIdentifier: String?
    let nutritionAvailabilityRawValue: Int?
}
