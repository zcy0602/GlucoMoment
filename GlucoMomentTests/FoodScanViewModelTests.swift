//
//  FoodScanViewModelTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
import UIKit

@testable import GlucoMoment

@Suite("拍照识别多图")
@MainActor
struct FoodScanViewModelTests {
    @Test("追加照片保留描述、作废旧结果，且不超过上限")
    func addPhotosKeepsContext() {
        let viewModel = makeViewModel()
        viewModel.selectPhotos([Data([0x01])])
        viewModel.userFoodContext = "四人合餐，我吃了一碗米饭"
        viewModel.result = Self.result
        viewModel.phase = .needsReview

        viewModel.addPhotos(Array(repeating: Data([0x02]), count: 5))

        #expect(viewModel.selectedPhotos.count == viewModel.maxPhotoCount)
        #expect(viewModel.selectedPhotos.first == Data([0x01]))
        #expect(viewModel.remainingPhotoSlots == 0)
        #expect(viewModel.userFoodContext == "四人合餐，我吃了一碗米饭")
        #expect(viewModel.result == nil)
        #expect(viewModel.phase == .awaitingContext)
    }

    @Test("重新选择照片会开始新的一餐")
    func selectPhotosResets() {
        let viewModel = makeViewModel()
        viewModel.selectPhotos([Data([0x01]), Data([0x02])])
        viewModel.userFoodContext = "旧描述"

        viewModel.selectPhotos([Data([0x03])])

        #expect(viewModel.selectedPhotos == [Data([0x03])])
        #expect(viewModel.userFoodContext.isEmpty)
    }

    @Test("删除照片后需要重新识别，删光后回到选择照片")
    func removePhotos() {
        let viewModel = makeViewModel()
        viewModel.selectPhotos([Data([0x01]), Data([0x02])])
        viewModel.result = Self.result
        viewModel.phase = .needsReview

        viewModel.removePhoto(at: 0)
        #expect(viewModel.selectedPhotos == [Data([0x02])])
        #expect(viewModel.result == nil)
        #expect(viewModel.phase == .awaitingContext)

        viewModel.removePhoto(at: 5)
        #expect(viewModel.selectedPhotos.count == 1)

        viewModel.removePhoto(at: 0)
        #expect(viewModel.selectedPhotos.isEmpty)
        #expect(viewModel.phase == .idle)
    }

    @Test("全部照片按顺序交给识别服务，保存时一起写入")
    func analyzesAndSavesAllPhotos() async throws {
        let service = RecordingFoodAnalysisService(result: Self.result)
        let repository = RecordingMealRepository()
        let photoStore = InMemoryMealPhotoStore()
        let viewModel = FoodScanViewModel(
            analysisService: service,
            mealRepository: repository,
            photoStore: photoStore
        )
        let photos = try [UIColor.red, .green, .blue].map(Self.jpeg)
        viewModel.selectPhotos(photos)

        viewModel.startAnalysis()
        var attempts = 0
        while viewModel.phase != .needsReview, attempts < 200 {
            try await Task.sleep(for: .milliseconds(20))
            attempts += 1
        }
        #expect(viewModel.phase == .needsReview)
        #expect(await service.receivedImageCounts == [3])

        await viewModel.save()

        #expect(viewModel.phase == .saved)
        let meal = try #require(repository.savedMeals.first)
        let filename = try #require(meal.photoFilename)
        let saved = await photoStore.allJPEGData(primaryFilename: filename)
        #expect(saved.count == 3)
        #expect(saved == (await service.receivedImages))
    }

    private func makeViewModel() -> FoodScanViewModel {
        FoodScanViewModel(
            analysisService: RecordingFoodAnalysisService(result: Self.result),
            mealRepository: RecordingMealRepository(),
            photoStore: InMemoryMealPhotoStore()
        )
    }

    private static func jpeg(_ color: UIColor) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    private static let result = FoodRecognitionResult(
        name: "合餐",
        confidence: 0.8,
        glucoseImpact: "中等",
        score: 60,
        items: [],
        suggestions: [],
        followUpQuestions: [],
        uncertainties: [],
        provider: "test",
        model: "test",
        promptVersion: "test"
    )
}

private actor RecordingFoodAnalysisService: FoodAnalysisService {
    private let result: FoodRecognitionResult
    private(set) var receivedImageCounts: [Int] = []
    private(set) var receivedImages: [Data] = []

    init(result: FoodRecognitionResult) {
        self.result = result
    }

    func analyze(
        images: [Data],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        receivedImageCounts.append(images.count)
        receivedImages = images
        return result
    }
}

@MainActor
private final class RecordingMealRepository: MealRepository {
    private(set) var savedMeals: [MealRecord] = []

    func meals(in interval: DateInterval, period: MealPeriod?) throws -> [MealRecord] {
        savedMeals
    }

    func save(_ meal: MealRecord) async throws {
        savedMeals.append(meal)
    }

    func delete(id: UUID) async throws {
        savedMeals.removeAll { $0.id == id }
    }
}
