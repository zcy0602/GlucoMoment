//
//  HealthKitGlucoseSyncServiceTests.swift
//  GlucoMomentTests
//

import Foundation
import HealthKit
import Testing
@testable import GlucoMoment

@Suite("HealthKit 血糖映射")
struct HealthKitStoreClientTests {
    @MainActor
    @Test("mg/dL 样本会转换为 mmol/L 并保留 HealthKit UUID")
    func convertsBloodGlucoseUnitAndIdentity() throws {
        let type = try #require(HKObjectType.quantityType(forIdentifier: .bloodGlucose))
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .init(from: "mg/dL"), doubleValue: 180.15588),
            start: measuredAt,
            end: measuredAt
        )

        let reading = HealthKitStoreClient.makeReading(from: sample)

        #expect(abs(reading.value - 10.0) < 0.001)
        #expect(reading.id == sample.uuid)
        #expect(reading.externalIdentifier == sample.uuid.uuidString)
        #expect(reading.source == .healthKit)
        #expect(reading.measuredAt == measuredAt)
    }

    @MainActor
    @Test("App 血糖写入保留本地记录 ID")
    func glucoseSampleCarriesLocalIdentity() throws {
        let id = UUID()
        let reading = GlucoseReading(
            id: id,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            value: 6.8
        )

        let sample = try HealthKitStoreClient.makeGlucoseSample(from: reading)

        #expect(sample.metadata?[HKMetadataKeyExternalUUID] as? String == id.uuidString)
        #expect(sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true)
    }
}
