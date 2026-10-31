//
//  MealReviewViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 复盘页的「AI 复盘」：未开启 → 数据不足 → 可以生成 → 生成中 → 显示结果。
/// 只在用户点按钮时调用模型。生成过就一直显示最近一份，有新的餐时提示可以重新生成；
/// 每次生成的结果存进本机历史
@MainActor
@Observable
final class MealReviewViewModel {
    enum State: Equatable {
        case disabled
        case loading
        case insufficient(mealCount: Int)
        case ready(mealCount: Int)
        case generating
        /// `serviceError` 不为 nil 时，模型调用失败，显示的是本地模板
        case loaded(MealReview, generatedAt: Date, serviceError: String?)
        case failed(String)
    }

    /// 少于这么多餐有 CGM 覆盖时不生成，复盘没有意义
    static let minimumMealCount = 3

    private(set) var state: State = .disabled
    /// 本机保存的复盘，从新到旧
    private(set) var history: [SavedMealReview] = []
    /// 卡片正在显示的那一份已保存的复盘；模型调用失败、显示本地模板时为 nil
    private(set) var shownReview: SavedMealReview?
    /// 最近 14 天有完整餐后血糖、可以发给模型的餐数
    private(set) var availableMealCount = 0
    /// 正在显示的复盘之后新出现的餐数，用来提示重新生成
    private(set) var newMealCount = 0

    private let glucoseRepository: any GlucoseRepository
    private let mealRepository: any MealRepository
    private let service: any MealReviewService
    private let settings: MealReviewSettings
    private let cache: any MealReviewCacheStoring
    private let now: () -> Date
    @ObservationIgnored private var payload: MealReviewPayload?
    /// 本次读到的餐，生成时用来记下覆盖的用餐时间
    @ObservationIgnored private var meals: [MealRecord] = []

    init(
        glucoseRepository: any GlucoseRepository,
        mealRepository: any MealRepository,
        service: any MealReviewService,
        settings: MealReviewSettings,
        cache: any MealReviewCacheStoring,
        now: @escaping () -> Date = { .now }
    ) {
        self.glucoseRepository = glucoseRepository
        self.mealRepository = mealRepository
        self.service = service
        self.settings = settings
        self.cache = cache
        self.now = now
    }

    var isEnabled: Bool { settings.isEnabled }

    /// 有足够的餐才能（重新）生成
    var canGenerate: Bool { availableMealCount >= Self.minimumMealCount }

    func load() async {
        guard settings.isEnabled else {
            payload = nil
            meals = []
            history = []
            shownReview = nil
            availableMealCount = 0
            newMealCount = 0
            state = .disabled
            return
        }
        if case .generating = state { return }

        let end = now()
        let interval = DateInterval(
            start: end.addingTimeInterval(-Double(MealReviewPayloadBuilder.reviewDays) * 86_400),
            end: end
        )
        let payload: MealReviewPayload
        do {
            let points = try glucoseRepository.readings(in: interval).map {
                GlucosePoint(time: $0.measuredAt, value: $0.value)
            }
            let meals = try mealRepository.meals(in: interval, period: nil)
            payload = MealReviewPayloadBuilder.build(meals: meals, points: points, targetRange: .current)
            self.meals = meals
        } catch {
            state = .failed("读取记录失败：\(error.localizedDescription)")
            return
        }
        self.payload = payload
        availableMealCount = payload.meals.count
        history = await cache.history()
        showLatest()
    }

    /// 模型调用失败时改用本地模板，并说明原因；这种结果不存进历史，方便稍后重试
    func generate() async {
        guard settings.isEnabled, let payload, payload.meals.count >= Self.minimumMealCount else { return }
        state = .generating

        do {
            let draft = try await service.review(payload)
            let review = MealReviewValidator.review(from: draft, payload: payload)
            let recordIDs = payload.meals.compactMap(\.recordID)
            let mealTimes = meals.filter { recordIDs.contains($0.id) }.map(\.eatenAt)
            let saved = SavedMealReview(
                generatedAt: now(),
                review: review,
                mealCount: payload.meals.count,
                firstMealAt: mealTimes.min(),
                lastMealAt: mealTimes.max(),
                mealRecordIDs: recordIDs
            )
            await cache.append(saved)
            history = await cache.history()
            showLatest()
        } catch is CancellationError {
            showLatest()
        } catch {
            let local = MealReviewDraft(items: [], provider: "local", model: "template", promptVersion: MealReviewPrompt.version)
            shownReview = nil
            state = .loaded(
                MealReviewValidator.review(from: local, payload: payload),
                generatedAt: now(),
                serviceError: error.localizedDescription
            )
        }
    }

    /// 先从界面上移除，再删文件，列表的删除动画不用等读写
    func deleteReviews(ids: Set<UUID>) async {
        history.removeAll { ids.contains($0.id) }
        for id in ids {
            await cache.delete(id: id)
        }
        if case .generating = state { return }
        history = await cache.history()
        showLatest()
    }

    /// 有历史就显示最近一份（数据不足时也显示），没有时按餐数显示生成按钮或数据不足
    private func showLatest() {
        guard let latest = history.first else {
            shownReview = nil
            newMealCount = 0
            state = canGenerate
                ? .ready(mealCount: availableMealCount)
                : .insufficient(mealCount: availableMealCount)
            return
        }
        shownReview = latest
        newMealCount = Self.newMealCount(since: latest, in: payload)
        state = .loaded(latest.review, generatedAt: latest.generatedAt, serviceError: nil)
    }

    /// 只看有没有新的餐：新读数、窗口滚动让旧餐移出去都不算。旧版迁移来的记录不知道用了哪些餐，按 0 算
    static func newMealCount(since review: SavedMealReview, in payload: MealReviewPayload?) -> Int {
        guard let reviewedIDs = review.mealRecordIDs.map(Set.init), let payload else { return 0 }
        return payload.meals.count { meal in
            meal.recordID.map { !reviewedIDs.contains($0) } ?? false
        }
    }

    func enable() async {
        settings.isEnabled = true
        await load()
    }
}
