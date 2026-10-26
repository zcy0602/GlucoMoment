//
//  MealReviewCacheStore.swift
//  GlucoMoment
//

import Foundation

/// 最近一次复盘。数据没变（payloadJSON 相同）时直接显示，不重复调用模型
nonisolated struct CachedMealReview: Codable, Hashable, Sendable {
    var payloadJSON: String
    var generatedAt: Date
    var review: MealReview
}

/// 只保存最近一次复盘，不写进 SwiftData；关闭 AI 复盘时删除
protocol MealReviewCacheStoring: Sendable {
    func load() async -> CachedMealReview?
    func save(_ cached: CachedMealReview) async
    func clear() async
}

actor LocalMealReviewCacheStore: MealReviewCacheStoring {
    private let fileURL: URL

    init(directoryURL: URL? = nil) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = directoryURL ?? applicationSupport
            .appendingPathComponent("GlucoMoment", isDirectory: true)
            .appendingPathComponent("MealReview", isDirectory: true)
        fileURL = directory.appendingPathComponent("latest.json")
    }

    func load() async -> CachedMealReview? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedMealReview.self, from: data)
    }

    /// 缓存写不进去只影响下次是否要重新生成，不打断流程
    func save(_ cached: CachedMealReview) async {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() async {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

actor InMemoryMealReviewCacheStore: MealReviewCacheStoring {
    private var cached: CachedMealReview?

    func load() async -> CachedMealReview? { cached }
    func save(_ cached: CachedMealReview) async { self.cached = cached }
    func clear() async { cached = nil }
}
