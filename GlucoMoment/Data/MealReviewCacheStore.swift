//
//  MealReviewCacheStore.swift
//  GlucoMoment
//

import Foundation

/// 保存下来的一份复盘。只存校验后的文字和覆盖范围，不存发给模型的数据（每餐曲线等）
nonisolated struct SavedMealReview: Codable, Hashable, Sendable, Identifiable {
    /// 最多保留这么多份，超出时删掉最旧的
    static let historyLimit = 20

    var id: UUID
    var generatedAt: Date
    var review: MealReview
    /// 这次复盘用到的餐数；从旧版缓存迁移、读不出餐数时为 0
    var mealCount: Int
    /// 用到的最早、最晚一餐的用餐时间；从旧版缓存迁移来的记录没有
    var firstMealAt: Date?
    var lastMealAt: Date?
    /// 用到的本机餐食记录 id，用来判断之后有没有新的餐；从旧版缓存迁移来的记录为 nil
    var mealRecordIDs: [UUID]?

    init(
        id: UUID = UUID(),
        generatedAt: Date,
        review: MealReview,
        mealCount: Int,
        firstMealAt: Date? = nil,
        lastMealAt: Date? = nil,
        mealRecordIDs: [UUID]? = nil
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.review = review
        self.mealCount = mealCount
        self.firstMealAt = firstMealAt
        self.lastMealAt = lastMealAt
        self.mealRecordIDs = mealRecordIDs
    }

    /// 插入后按生成时间从新到旧排列，只留最近 `historyLimit` 份
    static func inserting(_ review: SavedMealReview, into history: [SavedMealReview]) -> [SavedMealReview] {
        let merged = history.filter { $0.id != review.id } + [review]
        return Array(merged.sorted { $0.generatedAt > $1.generatedAt }.prefix(historyLimit))
    }
}

/// 复盘历史，存在本机 JSON 文件里，不写进 SwiftData；关闭 AI 复盘时全部删除。
/// 名字沿用只存最近一份时的「缓存」
protocol MealReviewCacheStoring: Sendable {
    /// 从新到旧
    func history() async -> [SavedMealReview]
    func append(_ review: SavedMealReview) async
    func delete(id: UUID) async
    func clear() async
}

actor LocalMealReviewCacheStore: MealReviewCacheStoring {
    /// 文件格式版本，以后改结构时据此兼容旧文件
    private nonisolated static let fileVersion = 1

    private nonisolated struct HistoryFile: Codable {
        var version: Int
        var reviews: [SavedMealReview]
    }

    /// 旧版只存最近一份，文件名 latest.json；第一次读历史时迁移过来
    private nonisolated struct LegacyCachedReview: Decodable {
        var payloadJSON: String
        var generatedAt: Date
        var review: MealReview
    }

    private let historyURL: URL
    private let legacyURL: URL

    init(directoryURL: URL? = nil) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = directoryURL ?? applicationSupport
            .appendingPathComponent("GlucoMoment", isDirectory: true)
            .appendingPathComponent("MealReview", isDirectory: true)
        historyURL = directory.appendingPathComponent("history.json")
        legacyURL = directory.appendingPathComponent("latest.json")
    }

    func history() async -> [SavedMealReview] {
        if let data = try? Data(contentsOf: historyURL),
           let file = try? JSONDecoder().decode(HistoryFile.self, from: data) {
            return file.reviews.sorted { $0.generatedAt > $1.generatedAt }
        }
        return migrateLegacy()
    }

    func append(_ review: SavedMealReview) async {
        write(SavedMealReview.inserting(review, into: await history()))
    }

    func delete(id: UUID) async {
        write(await history().filter { $0.id != id })
    }

    func clear() async {
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: legacyURL)
    }

    /// 把旧版的 latest.json 转成第一份历史；读不出来时当作没有历史
    private func migrateLegacy() -> [SavedMealReview] {
        guard let data = try? Data(contentsOf: legacyURL),
              let legacy = try? JSONDecoder().decode(LegacyCachedReview.self, from: data) else {
            return []
        }
        let payload = try? JSONDecoder().decode(MealReviewPayload.self, from: Data(legacy.payloadJSON.utf8))
        let migrated = [SavedMealReview(
            generatedAt: legacy.generatedAt,
            review: legacy.review,
            mealCount: payload?.meals.count ?? 0
        )]
        if write(migrated) {
            try? FileManager.default.removeItem(at: legacyURL)
        }
        return migrated
    }

    /// 写不进去只影响历史是否保留，不打断流程
    @discardableResult
    private func write(_ reviews: [SavedMealReview]) -> Bool {
        guard let data = try? JSONEncoder().encode(HistoryFile(version: Self.fileVersion, reviews: reviews)) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: historyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: historyURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }
}

actor InMemoryMealReviewCacheStore: MealReviewCacheStoring {
    private var reviews: [SavedMealReview] = []

    func history() async -> [SavedMealReview] { reviews }
    func append(_ review: SavedMealReview) async { reviews = SavedMealReview.inserting(review, into: reviews) }
    func delete(id: UUID) async { reviews.removeAll { $0.id == id } }
    func clear() async { reviews = [] }
}
