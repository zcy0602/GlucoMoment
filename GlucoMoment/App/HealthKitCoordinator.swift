//
//  HealthKitCoordinator.swift
//  GlucoMoment
//

import Foundation
import Observation

@MainActor
@Observable
final class HealthKitCoordinator {
    enum Sheet: String, Identifiable {
        case introduction

        var id: String { rawValue }
    }

    private enum PreferenceKey {
        static let hasSeenIntroduction = "healthKit.hasSeenIntroduction"
        static let hasRequestedAuthorization = "healthKit.hasRequestedAuthorization"
        static let authorizationVersion = "healthKit.authorizationVersion"
        static let introductionVersion = "healthKit.introductionVersion"
        static let lastSyncDate = "healthKit.lastSyncDate"
        static let lastSyncedGlucoseCount = "healthKit.lastSyncedGlucoseCount"
        static let lastSyncedMealCount = "healthKit.lastSyncedMealCount"
    }

    private static let currentAuthorizationVersion = 2

    private let service: any HealthKitSynchronizing
    private let defaults: UserDefaults
    private let presentsIntroduction: Bool
    private var hasHandledLaunch = false

    var presentedSheet: Sheet?
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncedGlucoseCount: Int?
    private(set) var lastSyncedMealCount: Int?
    private(set) var dataRevision = 0
    var errorMessage: String?
    var isShowingError = false

    init(
        service: any HealthKitSynchronizing,
        defaults: UserDefaults = .standard,
        presentsIntroduction: Bool = true
    ) {
        self.service = service
        self.defaults = defaults
        self.presentsIntroduction = presentsIntroduction
        self.lastSyncDate = defaults.object(forKey: PreferenceKey.lastSyncDate) as? Date
        if defaults.object(forKey: PreferenceKey.lastSyncedGlucoseCount) != nil {
            self.lastSyncedGlucoseCount = defaults.integer(forKey: PreferenceKey.lastSyncedGlucoseCount)
        }
        if defaults.object(forKey: PreferenceKey.lastSyncedMealCount) != nil {
            self.lastSyncedMealCount = defaults.integer(forKey: PreferenceKey.lastSyncedMealCount)
        }
    }

    var isHealthDataAvailable: Bool {
        service.isHealthDataAvailable
    }

    var statusText: String {
        if isSyncing {
            return "正在同步血糖与饮食数据…"
        }
        guard isHealthDataAvailable else {
            return "此设备不支持健康数据"
        }
        if let lastSyncDate, let lastSyncedGlucoseCount, let lastSyncedMealCount {
            return "上次同步 \(lastSyncDate.formatted(GlucoMomentDateStyle.relative))，\(lastSyncedGlucoseCount) 条血糖、\(lastSyncedMealCount) 条饮食"
        }
        return "尚未同步"
    }

    func handleLaunch() async {
        guard !hasHandledLaunch else { return }
        hasHandledLaunch = true

        let introductionVersion = defaults.integer(forKey: PreferenceKey.introductionVersion)
        if presentsIntroduction && introductionVersion < Self.currentAuthorizationVersion {
            presentedSheet = .introduction
            return
        }

        guard isHealthDataAvailable,
              defaults.integer(forKey: PreferenceKey.authorizationVersion)
                >= Self.currentAuthorizationVersion else {
            return
        }
        await synchronize(showErrors: false)
    }

    func authorizeAndSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await service.requestAuthorization()
            defaults.set(true, forKey: PreferenceKey.hasSeenIntroduction)
            defaults.set(true, forKey: PreferenceKey.hasRequestedAuthorization)
            defaults.set(
                Self.currentAuthorizationVersion,
                forKey: PreferenceKey.authorizationVersion
            )
            defaults.set(
                Self.currentAuthorizationVersion,
                forKey: PreferenceKey.introductionVersion
            )
            presentedSheet = nil
            try await performSync()
        } catch {
            presentedSheet = nil
            present(error)
        }
    }

    func useWithoutHealthKit() {
        defaults.set(true, forKey: PreferenceKey.hasSeenIntroduction)
        defaults.set(
            Self.currentAuthorizationVersion,
            forKey: PreferenceKey.introductionVersion
        )
        presentedSheet = nil
    }

    func synchronize(showErrors: Bool = true) async {
        guard !isSyncing, isHealthDataAvailable else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await performSync()
        } catch where showErrors {
            present(error)
        } catch {
            // 启动时静默失败，用户仍可在设置中主动重试并查看错误。
        }
    }

    private func performSync() async throws {
        let result = try await service.synchronize()
        lastSyncDate = result.synchronizedAt
        lastSyncedGlucoseCount = result.glucoseSampleCount
        lastSyncedMealCount = result.mealCount
        defaults.set(result.synchronizedAt, forKey: PreferenceKey.lastSyncDate)
        defaults.set(
            result.glucoseSampleCount,
            forKey: PreferenceKey.lastSyncedGlucoseCount
        )
        defaults.set(result.mealCount, forKey: PreferenceKey.lastSyncedMealCount)
        dataRevision += 1
    }

    private func present(_ error: any Error) {
        errorMessage = "HealthKit 操作失败：\(error.localizedDescription)"
        isShowingError = true
    }
}
