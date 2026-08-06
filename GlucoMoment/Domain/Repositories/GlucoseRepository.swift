//
//  GlucoseRepository.swift
//  GlucoMoment
//

import Foundation

@MainActor
protocol GlucoseRepository: AnyObject {
    func readings(in interval: DateInterval) throws -> [GlucoseReading]
    func latestReading() throws -> GlucoseReading?
    func save(_ reading: GlucoseReading) async throws
    func delete(id: UUID) async throws
    func replaceHealthKitReadings(with readings: [GlucoseReading]) throws
}
