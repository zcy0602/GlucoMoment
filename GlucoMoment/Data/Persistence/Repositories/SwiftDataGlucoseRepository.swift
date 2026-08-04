//
//  SwiftDataGlucoseRepository.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataGlucoseRepository: GlucoseRepository {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
    }

    func readings(in interval: DateInterval) throws -> [GlucoseReading] {
        let start = interval.start
        let end = interval.end
        let predicate = #Predicate<GlucoseSampleEntity> {
            $0.measuredAt >= start && $0.measuredAt < end
        }
        let descriptor = FetchDescriptor<GlucoseSampleEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.measuredAt)]
        )

        return try modelContext.fetch(descriptor).map(makeReading)
    }

    func latestReading() throws -> GlucoseReading? {
        var descriptor = FetchDescriptor<GlucoseSampleEntity>(
            sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first.map(makeReading)
    }

    func save(_ reading: GlucoseReading) throws {
        let readingID = reading.id
        let predicate = #Predicate<GlucoseSampleEntity> { $0.id == readingID }
        var descriptor = FetchDescriptor<GlucoseSampleEntity>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let entity = try modelContext.fetch(descriptor).first {
            update(entity, from: reading)
        } else {
            modelContext.insert(makeEntity(from: reading))
        }

        try modelContext.save()
    }

    func delete(id: UUID) throws {
        let readingID = id
        let predicate = #Predicate<GlucoseSampleEntity> { $0.id == readingID }
        var descriptor = FetchDescriptor<GlucoseSampleEntity>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let entity = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    private func makeReading(from entity: GlucoseSampleEntity) -> GlucoseReading {
        GlucoseReading(
            id: entity.id,
            measuredAt: entity.measuredAt,
            value: entity.value,
            source: GlucoseSource(rawValue: entity.sourceRawValue) ?? .manual,
            note: entity.note,
            externalIdentifier: entity.externalIdentifier
        )
    }

    private func makeEntity(from reading: GlucoseReading) -> GlucoseSampleEntity {
        let now = Date.now
        return GlucoseSampleEntity(
            id: reading.id,
            measuredAt: reading.measuredAt,
            timeZoneIdentifier: TimeZone.current.identifier,
            value: reading.value,
            sourceRawValue: reading.source.rawValue,
            externalIdentifier: reading.externalIdentifier,
            note: reading.note,
            createdAt: now,
            updatedAt: now
        )
    }

    private func update(_ entity: GlucoseSampleEntity, from reading: GlucoseReading) {
        entity.measuredAt = reading.measuredAt
        entity.timeZoneIdentifier = TimeZone.current.identifier
        entity.value = reading.value
        entity.sourceRawValue = reading.source.rawValue
        entity.externalIdentifier = reading.externalIdentifier
        entity.note = reading.note
        entity.updatedAt = .now
    }
}
