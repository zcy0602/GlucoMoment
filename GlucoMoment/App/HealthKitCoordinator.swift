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
    /// 回到前台时，距上次同步不足这么久就跳过，避免频繁切换 App 时反复读取 30 天的数据
    private static let foregroundSyncInterval: TimeInterval = 2 * 60

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

    /// 旧版设置页使用的整句状态
    var statusText: String {
        guard let syncedCountText else {
            return statusHeadline
        }
        return "\(statusHeadline)，\(syncedCountText)"
    }

    /// 同步状态的第一句：正在同步、不支持、上次同步时间或尚未同步
    var statusHeadline: String {
        if isSyncing {
            return "正在同步血糖与饮食数据…"
        }
        guard isHealthDataAvailable else {
            return "此设备不支持健康数据"
        }
        if let lastSyncDate {
            return "上次同步 \(lastSyncDate.formatted(GlucoMomentDateStyle.relative))"
        }
        return "尚未同步"
    }

    /// 上次同步的条数，新版设置页单独占一行显示；同步中或没有同步记录时为 nil
    var syncedCountText: String? {
        guard !isSyncing, isHealthDataAvailable, lastSyncDate != nil,
              let lastSyncedGlucoseCount, let lastSyncedMealCount else {
            return nil
        }
        return "\(lastSyncedGlucoseCount) 条血糖、\(lastSyncedMealCount) 条饮食"
    }

    func handleLaunch() async {
        guard !hasHandledLaunch else { return }
        hasHandledLaunch = true

        let introductionVersion = defaults.integer(forKey: PreferenceKey.introductionVersion)
        if presentsIntroduction && introductionVersion < Self.currentAuthorizationVersion {
            presentedSheet = .introduction
            return
        }

        guard hasAuthorizedCurrentVersion else { return }
        await synchronize(showErrors: false)
    }

    /// App 回到前台时调用。冷启动由 handleLaunch 负责；之后每次回到前台，
    /// 距上次同步超过 foregroundSyncInterval 才静默同步一次，以便拿到 CGM 新写入健康的数据
    func handleBecameActive() async {
        guard hasHandledLaunch, hasAuthorizedCurrentVersion else { return }
        if let lastSyncDate,
           Date.now.timeIntervalSince(lastSyncDate) < Self.foregroundSyncInterval {
            return
        }
        await synchronize(showErrors: false)
    }

    /// 页面下拉刷新时调用：用户主动操作，不节流，失败时提示。未授权时什么都不做，页面照常重新读取本地数据
    func refresh() async {
        guard hasAuthorizedCurrentVersion else { return }
        await synchronize(showErrors: true)
    }

    /// 用户已按当前版本的授权说明同意过，才允许自动同步；否则不能静默访问 HealthKit
    private var hasAuthorizedCurrentVersion: Bool {
        isHealthDataAvailable
            && defaults.integer(forKey: PreferenceKey.authorizationVersion)
                >= Self.currentAuthorizationVersion
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
