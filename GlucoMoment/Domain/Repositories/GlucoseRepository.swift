//
//  GlucoseRepository.swift
//  GlucoMoment
//

import Foundation

@MainActor
protocol GlucoseRepository: AnyObject {
    func readings(in interval: DateInterval) throws -> [GlucoseReading]
    func latestReading() throws -> GlucoseReading?
    func save(_ reading: GlucoseReading) throws
    func delete(id: UUID) throws
}
