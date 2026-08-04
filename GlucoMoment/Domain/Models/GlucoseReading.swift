//
//  GlucoseReading.swift
//  GlucoMoment
//

import Foundation

struct GlucoseReading: Identifiable, Hashable, Sendable {
    let id: UUID
    var measuredAt: Date
    var value: Double
    var source: GlucoseSource
    var note: String?
    var externalIdentifier: String?

    init(
        id: UUID = UUID(),
        measuredAt: Date,
        value: Double,
        source: GlucoseSource = .manual,
        note: String? = nil,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.value = value
        self.source = source
        self.note = note
        self.externalIdentifier = externalIdentifier
    }

    var state: GlucoseState {
        GlucoseTargetRange.standard.state(for: value)
    }
}
