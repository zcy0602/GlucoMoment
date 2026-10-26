//
//  MealReviewViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 趋势页的「近期复盘」：未开启 → 数据不足 → 可以生成 → 生成中 → 显示结果。
/// 只在用户点按钮时调用模型；数据没变时直接显示上次的结果
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

    private let glucoseRepository: any GlucoseRepository
    private let mealRepository: any MealRepository
    private let service: any MealReviewService
    private let settings: MealReviewSettings
    private let cache: any MealReviewCacheStoring
    private let now: () -> Date
    @ObservationIgnored private var payload: MealReviewPayload?

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

    func load() async {
        guard settings.isEnabled else {
            payload = nil
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
            payload = MealReviewPayloadBuilder.build(meals: meals, points: points)
        } catch {
            state = .failed("读取记录失败：\(error.localizedDescription)")
            return
        }
        self.payload = payload

        guard payload.meals.count >= Self.minimumMealCount else {
            state = .insufficient(mealCount: payload.meals.count)
            return
        }
        if let cached = await cache.load(), cached.payloadJSON == (try? MealReviewPrompt.payloadJSON(payload)) {
            state = .loaded(cached.review, generatedAt: cached.generatedAt, serviceError: nil)
        } else {
            state = .ready(mealCount: payload.meals.count)
        }
    }

    /// 模型调用失败时改用本地模板，并说明原因；这种结果不缓存，方便稍后重试
    func generate() async {
        guard settings.isEnabled, let payload, payload.meals.count >= Self.minimumMealCount else { return }
        state = .generating

        do {
            let draft = try await service.review(payload)
            let review = MealReviewValidator.review(from: draft, payload: payload)
            let generatedAt = now()
            if let json = try? MealReviewPrompt.payloadJSON(payload) {
                await cache.save(CachedMealReview(payloadJSON: json, generatedAt: generatedAt, review: review))
            }
            state = .loaded(review, generatedAt: generatedAt, serviceError: nil)
        } catch is CancellationError {
            state = .ready(mealCount: payload.meals.count)
        } catch {
            let local = MealReviewDraft(items: [], provider: "local", model: "template", promptVersion: MealReviewPrompt.version)
            state = .loaded(
                MealReviewValidator.review(from: local, payload: payload),
                generatedAt: now(),
                serviceError: error.localizedDescription
            )
        }
    }

    func enable() async {
        settings.isEnabled = true
        await load()
    }
}
