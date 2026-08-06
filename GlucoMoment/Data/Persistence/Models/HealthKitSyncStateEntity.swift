//
//  HealthKitSyncStateEntity.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@Model
final class HealthKitSyncStateEntity {
    #Unique<HealthKitSyncStateEntity>([\.recordID, \.recordKindRawValue])
    #Index<HealthKitSyncStateEntity>([\.syncStatusRawValue], [\.recordKindRawValue, \.syncStatusRawValue])

    var recordID: UUID
    var recordKindRawValue: String
    var syncStatusRawValue: String
    var externalIdentifier: String?
    var nutritionAvailabilityRawValue: Int?
    var updatedAt: Date

    init(
        recordID: UUID,
        recordKindRawValue: String,
        syncStatusRawValue: String,
        externalIdentifier: String?,
        nutritionAvailabilityRawValue: Int?,
        updatedAt: Date
    ) {
        self.recordID = recordID
        self.recordKindRawValue = recordKindRawValue
        self.syncStatusRawValue = syncStatusRawValue
        self.externalIdentifier = externalIdentifier
        self.nutritionAvailabilityRawValue = nutritionAvailabilityRawValue
        self.updatedAt = updatedAt
    }
}
