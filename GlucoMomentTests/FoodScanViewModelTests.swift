//
//  FoodScanViewModelTests.swift
//  GlucoMomentTests
//

import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

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

    @Test("保存时写入食物类别和按规则生成的建议")
    func savesCategoriesAndRuleSuggestions() async throws {
        let repository = RecordingMealRepository()
        let viewModel = FoodScanViewModel(
            analysisService: RecordingFoodAnalysisService(result: Self.result),
            mealRepository: repository,
            photoStore: InMemoryMealPhotoStore()
        )
        viewModel.selectPhotos([try Self.jpeg(.red)])
        let categorized = SuggestionFixtures.result(
            items: SuggestionFixtures.balancedItems,
            suggestions: ["模型建议"]
        )
        viewModel.result = categorized
        viewModel.phase = .needsReview

        await viewModel.save()

        #expect(viewModel.phase == .saved)
        let meal = try #require(repository.savedMeals.first)
        #expect(meal.items.map(\.foodCategory) == [.protein, .wholeGrainLegume, .vegetable])
        #expect(meal.suggestions == categorized.effectiveSuggestions)
        #expect(!meal.suggestions.contains("模型建议"))
    }

    @Test("修正带上描述和复核页的餐次，第一版不发照片；换照片后修正记录清空")
    func correctionRequestAndReset() async throws {
        let service = RecordingFoodAnalysisService(result: Self.result)
        let viewModel = FoodScanViewModel(
            analysisService: service,
            mealRepository: RecordingMealRepository(),
            photoStore: InMemoryMealPhotoStore()
        )
        viewModel.selectPhotos([try Self.jpeg(.red)])
        viewModel.userFoodContext = "两人合餐"
        let history = [FoodCorrectionTurn(instruction: "米饭吃了一半", reply: "已修改。")]

        _ = try await viewModel.correct(Self.result, instruction: "还有一个卤蛋", history: history, mealPeriod: .dinner)

        let request = try #require(await service.receivedCorrections.last)
        #expect(request.instruction == "还有一个卤蛋")
        #expect(request.history == history)
        #expect(request.userFoodContext == "两人合餐")
        #expect(request.mealPeriod == .dinner)
        #expect(request.images.isEmpty == !FoodScanViewModel.sendsPhotosWithCorrection)

        viewModel.correctionHistory = history
        viewModel.selectPhotos([try Self.jpeg(.blue)])
        #expect(viewModel.correctionHistory.isEmpty)
    }

    @Test("读取 EXIF 拍摄时间，按时区偏移换算；没有 EXIF 时返回 nil")
    func readsCaptureDate() throws {
        let photo = try Self.jpeg(.red, exifDate: "2026:10:26 12:30:00", offset: "+08:00")
        #expect(FoodImageProcessor.captureDate(of: photo) == Self.date("2026-10-26T04:30:00Z"))
        #expect(FoodImageProcessor.captureDate(of: try Self.jpeg(.red)) == nil)
    }

    @Test("用餐时间取最早一张照片的拍摄时间；旧照片和未来时间不采用")
    func eatenAtFromCaptureDate() throws {
        let now = Self.date("2026-10-26T06:00:00Z")
        let viewModel = makeViewModel()

        viewModel.selectPhotos(
            [
                try Self.jpeg(.red, exifDate: "2026:10:26 12:40:00", offset: "+08:00"),
                try Self.jpeg(.green, exifDate: "2026:10:26 12:30:00", offset: "+08:00"),
                try Self.jpeg(.blue)
            ],
            referenceDate: now
        )
        #expect(viewModel.eatenAt == Self.date("2026-10-26T04:30:00Z"))
        #expect(viewModel.isEatenAtFromPhoto)

        viewModel.selectPhotos([try Self.jpeg(.red, exifDate: "2026:09:01 12:30:00", offset: "+08:00")], referenceDate: now)
        #expect(viewModel.eatenAt == now)
        #expect(!viewModel.isEatenAtFromPhoto)

        viewModel.selectPhotos([try Self.jpeg(.red, exifDate: "2026:10:26 18:00:00", offset: "+08:00")], referenceDate: now)
        #expect(viewModel.eatenAt == now)

        viewModel.selectPhotos([try Self.jpeg(.red)], referenceDate: now)
        #expect(viewModel.eatenAt == now)
        #expect(!viewModel.isEatenAtFromPhoto)
    }

    @Test("上传前的压缩会去掉 EXIF")
    func preparedPhotoHasNoCaptureDate() async throws {
        let photo = try Self.jpeg(.red, exifDate: "2026:10:26 12:30:00", offset: "+08:00")
        let prepared = try await FoodImageProcessor.prepareForAnalysis(photo)
        #expect(FoodImageProcessor.captureDate(of: prepared) == nil)
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

    /// 生成带 EXIF 拍摄时间的 JPEG，模拟从相册读到的原图
    private static func jpeg(_ color: UIColor, exifDate: String, offset: String) throws -> Data {
        let plain = try jpeg(color)
        let source = try #require(CGImageSourceCreateWithData(plain as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: exifDate,
                kCGImagePropertyExifOffsetTimeOriginal: offset
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func date(_ iso8601: String) -> Date {
        try! Date(iso8601, strategy: .iso8601)
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

    func correct(_ request: FoodCorrectionRequest) async throws -> FoodCorrectionOutcome {
        receivedCorrections.append(request)
        return FoodCorrectionOutcome(result: request.current, reply: "已修改。", changedItemIDs: [])
    }

    private(set) var receivedCorrections: [FoodCorrectionRequest] = []
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
