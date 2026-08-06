//
//  HealthKitCoordinatorTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@Suite("HealthKit 首次引导", .serialized)
@MainActor
struct HealthKitCoordinatorTests {
    @Test("首次启动展示说明，选择暂不使用后不再重复展示")
    func presentsIntroductionOnlyOnce() async throws {
        let suiteName = "GlucoMomentTests.HealthKit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = StubHealthKitSynchronizationService()

        let firstCoordinator = HealthKitCoordinator(service: service, defaults: defaults)
        await firstCoordinator.handleLaunch()
        #expect(firstCoordinator.presentedSheet == .introduction)
        #expect(service.syncCallCount == 0)

        firstCoordinator.useWithoutHealthKit()

        let nextCoordinator = HealthKitCoordinator(service: service, defaults: defaults)
        await nextCoordinator.handleLaunch()
        #expect(nextCoordinator.presentedSheet == nil)
        #expect(service.syncCallCount == 0)
    }

    @Test("确认授权后请求系统权限并同步数据")
    func authorizesAndSynchronizes() async throws {
        let suiteName = "GlucoMomentTests.HealthKit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = StubHealthKitSynchronizationService(
            glucoseSampleCount: 12,
            mealCount: 4
        )
        let coordinator = HealthKitCoordinator(service: service, defaults: defaults)

        await coordinator.handleLaunch()
        await coordinator.authorizeAndSync()

        #expect(service.authorizationCallCount == 1)
        #expect(service.syncCallCount == 1)
        #expect(coordinator.lastSyncedGlucoseCount == 12)
        #expect(coordinator.lastSyncedMealCount == 4)
        #expect(coordinator.dataRevision == 1)
        #expect(coordinator.presentedSheet == nil)

        let relaunchedCoordinator = HealthKitCoordinator(service: service, defaults: defaults)
        await relaunchedCoordinator.handleLaunch()
        #expect(service.syncCallCount == 2)
    }
}

@MainActor
private final class StubHealthKitSynchronizationService: HealthKitSynchronizing {
    let isHealthDataAvailable = true
    let glucoseSampleCount: Int
    let mealCount: Int
    private(set) var authorizationCallCount = 0
    private(set) var syncCallCount = 0

    init(glucoseSampleCount: Int = 0, mealCount: Int = 0) {
        self.glucoseSampleCount = glucoseSampleCount
        self.mealCount = mealCount
    }

    func requestAuthorization() async throws {
        authorizationCallCount += 1
    }

    func synchronize() async throws -> HealthKitSynchronizationResult {
        syncCallCount += 1
        return HealthKitSynchronizationResult(
            glucoseSampleCount: glucoseSampleCount,
            mealCount: mealCount,
            synchronizedAt: .now
        )
    }
}
