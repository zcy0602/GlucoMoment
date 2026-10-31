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

    @Test("点生成才调用模型；结果校验后存进历史，重新打开时直接显示")
    func generatesAndSaves() async throws {
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

        let saved = try #require(await cache.history().first)
        #expect(saved.mealCount == 3)
        #expect(saved.mealRecordIDs.map(Set.init) == Set(Self.meals.prefix(3).map(\.id)))
        #expect(saved.firstMealAt == Self.meals[0].eatenAt)
        #expect(saved.lastMealAt == Self.meals[2].eatenAt)
        #expect(viewModel.shownReview == saved)
        #expect(viewModel.history == [saved])

        let (reopened, reopenedService, _) = Self.make(cache: cache)
        await reopened.load()
        guard case .loaded = reopened.state else {
            Issue.record("应直接显示保存的复盘，实际为 \(reopened.state)")
            return
        }
        #expect(reopened.newMealCount == 0)
        #expect(await reopenedService.callCount == 0)
    }

    @Test("同步了新读数仍显示上次的结果；多了有餐后血糖的餐时提示重新生成")
    func keepsResultAndCountsNewMeals() async {
        let (viewModel, _, cache) = Self.make()
        await viewModel.load()
        await viewModel.generate()

        // 只多了读数（没有新的餐）：summary 变了，但不算新数据
        let extraReadings = Fixture.points(Fixture.steadyStart, around: Fixture.date(month: 10, day: 25, hour: 3))
            .map { GlucoseReading(measuredAt: $0.time, value: $0.value, source: .healthKit) }
        let (synced, _, _) = Self.make(readings: Self.readings + extraReadings, cache: cache)
        await synced.load()
        guard case .loaded = synced.state else {
            Issue.record("应显示上次的结果，实际为 \(synced.state)")
            return
        }
        #expect(synced.newMealCount == 0)

        // 10-23 早餐补上了 CGM，成为一餐新的
        let breakfastReadings = Fixture.points(Fixture.steadyStart, around: Fixture.date(month: 10, day: 23, hour: 8))
            .map { GlucoseReading(measuredAt: $0.time, value: $0.value, source: .healthKit) }
        let (withNewMeal, _, _) = Self.make(readings: Self.readings + breakfastReadings, cache: cache)
        await withNewMeal.load()
        guard case .loaded = withNewMeal.state else {
            Issue.record("应显示上次的结果，实际为 \(withNewMeal.state)")
            return
        }
        #expect(withNewMeal.newMealCount == 1)
        #expect(withNewMeal.availableMealCount == 4)
    }

    @Test("有历史时，即使现在数据不足也显示最近一份，但不能重新生成")
    func showsHistoryWhenInsufficient() async {
        let (viewModel, _, cache) = Self.make()
        await viewModel.load()
        await viewModel.generate()

        let (later, _, _) = Self.make(meals: Array(Self.meals.prefix(2)), cache: cache)
        await later.load()
        guard case .loaded = later.state else {
            Issue.record("应显示保存的复盘，实际为 \(later.state)")
            return
        }
        #expect(!later.canGenerate)
    }

    @Test("删除最近一份后显示上一份；全部删掉后回到生成按钮")
    func deletesHistory() async throws {
        let cache = InMemoryMealReviewCacheStore()
        let older = SavedMealReview(generatedAt: Self.now.addingTimeInterval(-86_400), review: Self.review, mealCount: 3)
        let newer = SavedMealReview(generatedAt: Self.now.addingTimeInterval(-3_600), review: Self.review, mealCount: 3)
        await cache.append(older)
        await cache.append(newer)

        let (viewModel, _, _) = Self.make(cache: cache)
        await viewModel.load()
        #expect(viewModel.shownReview == newer)

        await viewModel.deleteReviews(ids: [newer.id])
        #expect(viewModel.shownReview == older)
        #expect(viewModel.history == [older])

        await viewModel.deleteReviews(ids: [older.id])
        #expect(viewModel.history.isEmpty)
        #expect(viewModel.state == .ready(mealCount: 3))
    }

    @Test("模型调用失败时改用本地模板并说明原因，不存进历史")
    func fallsBackWhenServiceFails() async {
        let (viewModel, _, cache) = Self.make(service: StubReviewService(outcome: .failure(.networkUnavailable)))
        await viewModel.load()
        await viewModel.generate()

        guard case .loaded(let review, _, let serviceError) = viewModel.state else {
            Issue.record("应显示本地模板，实际为 \(viewModel.state)")
            return
        }
        #expect(review.isFallback)
        #expect(!review.items.isEmpty)
        #expect(serviceError == FoodAnalysisError.networkUnavailable.localizedDescription)
        #expect(viewModel.shownReview == nil)
        #expect(await cache.history().isEmpty)
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

    static var review: MealReview {
        MealReviewValidator.review(from: validDraft, payload: MealReviewPayloadBuilderTests.payload)
    }

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
        readings: [GlucoseReading]? = nil,
        service: StubReviewService? = nil,
        cache: InMemoryMealReviewCacheStore? = nil
    ) -> (MealReviewViewModel, StubReviewService, InMemoryMealReviewCacheStore) {
        let service = service ?? StubReviewService(outcome: .success(validDraft))
        let cache = cache ?? InMemoryMealReviewCacheStore()
        let viewModel = MealReviewViewModel(
            glucoseRepository: StubGlucoseRepository(readings: readings ?? Self.readings),
            mealRepository: StubMealRepository(meals: meals ?? Self.meals),
            service: service,
            settings: MealReviewSettings(isEnabled: enabled),
            cache: cache,
            now: { now }
        )
        return (viewModel, service, cache)
    }
}

@Suite("复盘开关与本机历史")
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

    @Test("历史写入文件后可以读回，删除单份，关闭时全部删除")
    func historyRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalMealReviewCacheStore(directoryURL: directory)
        let older = SavedMealReview(
            generatedAt: MealReviewViewModelTests.now.addingTimeInterval(-86_400),
            review: MealReviewViewModelTests.review,
            mealCount: 3,
            firstMealAt: MealReviewViewModelTests.meals[0].eatenAt,
            lastMealAt: MealReviewViewModelTests.meals[2].eatenAt,
            mealRecordIDs: MealReviewViewModelTests.meals.prefix(3).map(\.id)
        )
        let newer = SavedMealReview(generatedAt: MealReviewViewModelTests.now, review: MealReviewViewModelTests.review, mealCount: 4)

        await store.append(older)
        await store.append(newer)
        #expect(await LocalMealReviewCacheStore(directoryURL: directory).history() == [newer, older])

        await store.delete(id: newer.id)
        #expect(await store.history() == [older])

        await store.clear()
        #expect(await store.history().isEmpty)
    }

    @Test("旧版只存最近一份的 latest.json 迁移为第一份历史")
    func migratesLegacyCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        struct Legacy: Encodable {
            var payloadJSON: String
            var generatedAt: Date
            var review: MealReview
        }
        let payload = MealReviewPayloadBuilderTests.payload
        let legacy = Legacy(
            payloadJSON: try MealReviewPrompt.payloadJSON(payload),
            generatedAt: MealReviewViewModelTests.now,
            review: MealReviewViewModelTests.review
        )
        let legacyURL = directory.appendingPathComponent("latest.json")
        try JSONEncoder().encode(legacy).write(to: legacyURL)

        let history = await LocalMealReviewCacheStore(directoryURL: directory).history()
        let migrated = try #require(history.first)
        #expect(history.count == 1)
        #expect(migrated.generatedAt == MealReviewViewModelTests.now)
        #expect(migrated.review == MealReviewViewModelTests.review)
        #expect(migrated.mealCount == payload.meals.count)
        #expect(migrated.mealRecordIDs == nil)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(await LocalMealReviewCacheStore(directoryURL: directory).history() == history)
    }

    @Test("历史最多保留 20 份，超出时删掉最旧的")
    func historyLimit() async {
        let store = InMemoryMealReviewCacheStore()
        let reviews = (0...SavedMealReview.historyLimit).map { offset in
            SavedMealReview(
                generatedAt: MealReviewViewModelTests.now.addingTimeInterval(Double(offset) * 3_600),
                review: MealReviewViewModelTests.review,
                mealCount: 3
            )
        }
        for review in reviews {
            await store.append(review)
        }

        let history = await store.history()
        #expect(history.count == SavedMealReview.historyLimit)
        #expect(history.first == reviews.last)
        #expect(!history.contains(reviews[0]))
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
