//
//  GlucoseRepositoryTests.swift
//  GlucoMomentTests
//

import Foundation
import SwiftData
import Testing
@testable import GlucoMoment

extension PersistenceRepositoryTests {
    @Suite("血糖仓库")
    @MainActor
    struct GlucoseRepositoryTests {
    @Test("保存后可以按时间范围读取")
    func savesAndFetchesReading() throws {
        let (container, repository) = try makeRepository()
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = GlucoseReading(measuredAt: measuredAt, value: 6.2, note: "早餐后")

        try repository.save(reading)

        let interval = DateInterval(start: measuredAt.addingTimeInterval(-1), end: measuredAt.addingTimeInterval(1))
        let fetched = try repository.readings(in: interval)
        let stored = try #require(fetched.first)

        #expect(fetched.count == 1)
        #expect(stored.id == reading.id)
        #expect(stored.value == 6.2)
        #expect(stored.note == "早餐后")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<GlucoseSampleEntity>()) == 1)
    }

    @Test("相同业务 ID 保存时更新而不是重复插入")
    func updatesExistingReading() throws {
        let (_, repository) = try makeRepository()
        let id = UUID()
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)

        try repository.save(GlucoseReading(id: id, measuredAt: measuredAt, value: 5.8))
        try repository.save(GlucoseReading(id: id, measuredAt: measuredAt, value: 7.1, note: "已校正"))

        let interval = DateInterval(start: measuredAt.addingTimeInterval(-1), end: measuredAt.addingTimeInterval(1))
        let fetched = try repository.readings(in: interval)
        let stored = try #require(fetched.first)

        #expect(fetched.count == 1)
        #expect(stored.value == 7.1)
        #expect(stored.note == "已校正")
    }

    @Test("读取结果按测量时间升序排列")
    func sortsReadingsByMeasurementDate() throws {
        let (_, repository) = try makeRepository()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let readings = [
            GlucoseReading(measuredAt: start.addingTimeInterval(120), value: 7.0),
            GlucoseReading(measuredAt: start, value: 5.5),
            GlucoseReading(measuredAt: start.addingTimeInterval(60), value: 6.1)
        ]
        for reading in readings {
            try repository.save(reading)
        }

        let fetched = try repository.readings(
            in: DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(121))
        )

        #expect(fetched.map(\.value) == [5.5, 6.1, 7.0])
    }

    @Test("删除记录后数据库不再返回该记录")
    func deletesReading() throws {
        let (_, repository) = try makeRepository()
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = GlucoseReading(measuredAt: measuredAt, value: 6.2)
        try repository.save(reading)

        try repository.delete(id: reading.id)

        let interval = DateInterval(start: measuredAt.addingTimeInterval(-1), end: measuredAt.addingTimeInterval(1))
        #expect(try repository.readings(in: interval).isEmpty)
        #expect(try repository.latestReading() == nil)
    }

    @Test("HealthKit 全量对账会更新外部样本但保留手动记录")
    func reconcilesHealthKitReadingsWithoutChangingManualReadings() throws {
        let (_, repository) = try makeRepository()
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let removedHealthKitID = UUID()
        let retainedHealthKitID = UUID()
        let manualReading = GlucoseReading(measuredAt: measuredAt, value: 5.6)

        try repository.save(manualReading)
        try repository.replaceHealthKitReadings(with: [
            GlucoseReading(
                id: removedHealthKitID,
                measuredAt: measuredAt,
                value: 6.0,
                source: .healthKit,
                externalIdentifier: removedHealthKitID.uuidString
            ),
            GlucoseReading(
                id: retainedHealthKitID,
                measuredAt: measuredAt.addingTimeInterval(60),
                value: 6.5,
                source: .healthKit,
                externalIdentifier: retainedHealthKitID.uuidString
            )
        ])

        try repository.replaceHealthKitReadings(with: [
            GlucoseReading(
                id: retainedHealthKitID,
                measuredAt: measuredAt.addingTimeInterval(60),
                value: 7.2,
                source: .healthKit,
                externalIdentifier: retainedHealthKitID.uuidString
            )
        ])

        let fetched = try repository.readings(
            in: DateInterval(
                start: measuredAt.addingTimeInterval(-1),
                end: measuredAt.addingTimeInterval(120)
            )
        )

        #expect(fetched.count == 2)
        #expect(fetched.contains(where: { $0.id == manualReading.id && $0.value == 5.6 }))
        #expect(fetched.contains(where: { $0.id == retainedHealthKitID && $0.value == 7.2 }))
        #expect(!fetched.contains(where: { $0.id == removedHealthKitID }))
    }

    @Test("HealthKit 对账只删除查询范围内的外部样本，范围外的历史保留")
    func reconcilesOnlyWithinQueriedWindow() throws {
        let (_, repository) = try makeRepository()
        let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
        let olderID = UUID()
        let removedID = UUID()

        func healthKitReading(_ id: UUID, at date: Date) -> GlucoseReading {
            GlucoseReading(
                id: id,
                measuredAt: date,
                value: 6.0,
                source: .healthKit,
                externalIdentifier: id.uuidString
            )
        }

        try repository.replaceHealthKitReadings(with: [
            healthKitReading(olderID, at: windowStart.addingTimeInterval(-3600)),
            healthKitReading(removedID, at: windowStart.addingTimeInterval(3600))
        ])

        // 新快照只覆盖 windowStart 之后，且两条都没查到
        try repository.replaceHealthKitReadings(with: [], since: windowStart)

        let fetched = try repository.readings(
            in: DateInterval(
                start: windowStart.addingTimeInterval(-7200),
                end: windowStart.addingTimeInterval(7200)
            )
        )

        #expect(fetched.map(\.id) == [olderID])
    }

    private func makeRepository() throws -> (ModelContainer, SwiftDataGlucoseRepository) {
        let container = PersistenceRepositoryTests.container
        try PersistenceRepositoryTests.resetStore()
        return (container, SwiftDataGlucoseRepository(modelContainer: container))
    }
    }
}
