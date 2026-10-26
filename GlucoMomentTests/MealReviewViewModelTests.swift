//
//  MealReviewViewModelTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing

@testable import GlucoMoment

@Suite("趋势页的近期复盘")
@MainActor
struct MealReviewViewModelTests {
    typealias Fixture = ResponseFixtures

    /// 10-26 中午，三餐都在最近 14 天内
    static let now = Fixture.date(month: 10, day: 26, hour: 12)

    @Test("未开启时不读取数据")
    func disabled() async {
        let (viewModel, service, _) = Self.make(enabled: false)
        await viewModel.load()

        #expect(viewModel.state == .disabled)
        #expect(await service.callCount == 0)
    }

    @Test("有 CGM 覆盖的餐不到 3 餐时提示数据不足")
    func insufficientMeals() async {
        let (viewModel, _, _) = Self.make(meals: Array(Self.meals.prefix(2)))
        await viewModel.load()

        #expect(viewModel.state == .insufficient(mealCount: 2))
    }

    @Test("点生成才调用模型；结果校验后保存，数据没变时直接显示上次的结果")
    func generatesAndCaches() async throws {
        let (viewModel, service, cache) = Self.make()
        await viewModel.load()
        #expect(viewModel.state == .ready(mealCount: 3))
        #expect(await service.callCount == 0)

        await viewModel.generate()

        guard case .loaded(let review, _, let serviceError) = viewModel.state else {
            Issue.record("应显示结果，实际为 \(viewModel.state)")
            return
        }
        #expect(serviceError == nil)
        #expect(!review.isFallback)
        #expect(review.items.map(\.text) == ["10-21（周三）晚餐的峰值升幅 5.5，可以把一部分主食换成杂粮再看看。"])
        #expect(await cache.load() != nil)

        let (reopened, reopenedService, _) = Self.make(cache: cache)
        await reopened.load()
        guard case .loaded = reopened.state else {
            Issue.record("应直接显示缓存，实际为 \(reopened.state)")
            return
        }
        #expect(await reopenedService.callCount == 0)
    }

    @Test("模型调用失败时改用本地模板并说明原因，不缓存")
    func fallsBackWhenServiceFails() async {
        let (viewModel, _, cache) = Self.make(service: StubReviewService(outcome: .failure(.networkUnavailable)))
        await viewModel.load()
        await viewModel.generate()

        guard case .loaded(let review, _, let serviceError) = viewModel.state else {
            Issue.record("应显示本地模板，实际为 \(viewModel.state)")
            return
        }
        #expect(review.isFallback)
        #expect(review.items.count == 3)
        #expect(serviceError == FoodAnalysisError.networkUnavailable.localizedDescription)
        #expect(await cache.load() == nil)
    }

    @Test("在趋势页同意开启后立即读取数据")
    func enableLoads() async {
        let (viewModel, _, _) = Self.make(enabled: false)
        await viewModel.enable()

        #expect(viewModel.isEnabled)
        #expect(viewModel.state == .ready(mealCount: 3))
    }

    // MARK: - 数据

    /// 与 MealReviewPayloadBuilderTests 相同：三餐有 CGM 覆盖，一餐只有指尖血，一餐餐后有低读数
    static let meals: [MealRecord] = {
        let builderMeals: [(Date, MealPeriod, [FoodRecognitionItem])] = [
            (Fixture.date(month: 10, day: 20, hour: 12), .lunch, []),
            (Fixture.date(month: 10, day: 21, hour: 20), .dinner, [SuggestionFixtures.item(.refinedGrain, 200, carbs: 52, fiber: 0.6, protein: 5)]),
            (Fixture.date(month: 10, day: 22, hour: 12), .lunch, SuggestionFixtures.balancedItems),
            (Fixture.date(month: 10, day: 23, hour: 8), .breakfast, SuggestionFixtures.balancedItems),
            (Fixture.date(month: 10, day: 24, hour: 19), .dinner, SuggestionFixtures.balancedItems),
        ]
        return builderMeals.map { eatenAt, period, items in
            MealRecord(
                eatenAt: eatenAt,
                mealPeriod: period,
                title: "测试餐",
                source: .aiPhoto,
                caloriesKcal: 0, carbohydratesGrams: 0, proteinGrams: 0, fatGrams: 0, fiberGrams: 0,
                items: items.map {
                    MealFoodItem(
                        id: $0.id, name: $0.name, portionDescription: "", estimatedGrams: $0.estimatedGrams,
                        caloriesKcal: 0, carbohydratesGrams: $0.carbohydratesGrams, proteinGrams: $0.proteinGrams,
                        fatGrams: 0, fiberGrams: $0.fiberGrams, foodCategory: $0.foodCategory
                    )
                }
            )
        }
    }()

    static let readings: [GlucoseReading] = {
        let points = Fixture.points(Fixture.slightlyEarly, around: Fixture.date(month: 10, day: 20, hour: 12))
            + Fixture.points(Fixture.earlyStart, around: Fixture.date(month: 10, day: 21, hour: 20))
            + Fixture.points(Fixture.steadyStart, around: Fixture.date(month: 10, day: 22, hour: 12))
            + Fixture.points(Fixture.lowAfterMeal, around: Fixture.date(month: 10, day: 24, hour: 19))
        return points.map { GlucoseReading(measuredAt: $0.time, value: $0.value, source: .healthKit) }
    }()

    static let validDraft = MealReviewDraft(
        items: [MealReviewDraftItem(
            text: "{M2.when}的峰值升幅 {M2.peakRise}，可以把一部分主食换成杂粮再看看。",
            mealIds: [],
            comparisonIds: [],
            guidelineId: "G3a"
        )],
        provider: "test",
        model: "test-model",
        promptVersion: MealReviewPrompt.version
    )

    /// 默认参数在非隔离环境求值，不能调用主线程隔离的初始化方法，所以在函数体里补默认值
    private static func make(
        enabled: Bool = true,
        meals: [MealRecord]? = nil,
        service: StubReviewService? = nil,
        cache: InMemoryMealReviewCacheStore? = nil
    ) -> (MealReviewViewModel, StubReviewService, InMemoryMealReviewCacheStore) {
        let service = service ?? StubReviewService(outcome: .success(validDraft))
        let cache = cache ?? InMemoryMealReviewCacheStore()
        let viewModel = MealReviewViewModel(
            glucoseRepository: StubGlucoseRepository(readings: readings),
            mealRepository: StubMealRepository(meals: meals ?? Self.meals),
            service: service,
            settings: MealReviewSettings(isEnabled: enabled),
            cache: cache,
            now: { now }
        )
        return (viewModel, service, cache)
    }
}

@Suite("复盘开关与本机缓存")
@MainActor
struct MealReviewSettingsTests {
    @Test("开关默认关闭，并保存在本机偏好里")
    func persistsSwitch() throws {
        let suite = "GlucoMomentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = MealReviewSettings(defaults: defaults)
        #expect(!settings.isEnabled)
        settings.isEnabled = true
        #expect(MealReviewSettings(defaults: defaults).isEnabled)
    }

    @Test("缓存写入文件后可以读回，关闭时删除")
    func cacheRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalMealReviewCacheStore(directoryURL: directory)
        let review = MealReviewValidator.review(
            from: MealReviewViewModelTests.validDraft,
            payload: MealReviewPayloadBuilderTests.payload
        )
        let cached = CachedMealReview(payloadJSON: "{}", generatedAt: MealReviewViewModelTests.now, review: review)

        await store.save(cached)
        #expect(await store.load() == cached)

        await store.clear()
        #expect(await store.load() == nil)
    }
}

private actor StubReviewService: MealReviewService {
    private let outcome: Result<MealReviewDraft, FoodAnalysisError>
    private(set) var callCount = 0

    init(outcome: Result<MealReviewDraft, FoodAnalysisError>) {
        self.outcome = outcome
    }

    func review(_ payload: MealReviewPayload) async throws -> MealReviewDraft {
        callCount += 1
        return try outcome.get()
    }
}

@MainActor
private final class StubGlucoseRepository: GlucoseRepository {
    private let storedReadings: [GlucoseReading]

    init(readings: [GlucoseReading]) {
        storedReadings = readings
    }

    func readings(in interval: DateInterval) throws -> [GlucoseReading] {
        storedReadings.filter { interval.contains($0.measuredAt) }
    }

    func latestReading() throws -> GlucoseReading? { storedReadings.last }
    func save(_ reading: GlucoseReading) async throws {}
    func delete(id: UUID) async throws {}
    func replaceHealthKitReadings(with readings: [GlucoseReading]) throws {}
}

@MainActor
private final class StubMealRepository: MealRepository {
    private let storedMeals: [MealRecord]

    init(meals: [MealRecord]) {
        storedMeals = meals
    }

    func meals(in interval: DateInterval, period: MealPeriod?) throws -> [MealRecord] {
        storedMeals.filter { interval.contains($0.eatenAt) }
    }

    func save(_ meal: MealRecord) async throws {}
    func delete(id: UUID) async throws {}
}
