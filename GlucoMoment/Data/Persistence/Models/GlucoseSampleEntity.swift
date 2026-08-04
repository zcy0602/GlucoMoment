//
//  GlucoseSampleEntity.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@Model
final class GlucoseSampleEntity {
    #Unique<GlucoseSampleEntity>([\.id])
    #Index<GlucoseSampleEntity>([\.measuredAt], [\.sourceRawValue, \.measuredAt], [\.externalIdentifier])

    var id: UUID
    var measuredAt: Date
    var timeZoneIdentifier: String
    var value: Double
    var sourceRawValue: String
    var externalIdentifier: String?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        measuredAt: Date,
        timeZoneIdentifier: String,
        value: Double,
        sourceRawValue: String,
        externalIdentifier: String?,
        note: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.value = value
        self.sourceRawValue = sourceRawValue
        self.externalIdentifier = externalIdentifier
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
