//
//  FoodScanViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/7/6.
//

import Foundation
import Observation

@MainActor
@Observable
final class FoodScanViewModel {
    let title = "拍照识别"

    private let analysisService: any FoodAnalysisService
    private let mealRepository: any MealRepository
    private let photoStore: any MealPhotoStoring
    private var analysisTask: Task<Void, Never>?
    /// 与 `selectedPhotos` 一一对应的压缩结果；照片增删后清空，下次识别或保存时重新生成
    private var preparedPhotos: [Data] = []
    /// 每次增删照片时递增，用来判断压缩结果是否仍对应当前照片
    private var photoRevision = 0

    let maxPhotoCount = FoodAnalysisImageLimit.maxImageCount

    var phase: FoodScanPhase = .idle
    /// 同一餐按添加顺序排列的原始照片，最多 `maxPhotoCount` 张
    var selectedPhotos: [Data] = []
    var userFoodContext = ""
    var result: FoodRecognitionResult?
    var selectedMealPeriod: MealPeriod
    var eatenAt = Date.now
    var userNote = ""

    init(
        analysisService: any FoodAnalysisService,
        mealRepository: any MealRepository,
        photoStore: any MealPhotoStoring,
        referenceDate: Date = .now
    ) {
        self.analysisService = analysisService
        self.mealRepository = mealRepository
        self.photoStore = photoStore
        selectedMealPeriod = MealPeriod.inferred(for: referenceDate)
        eatenAt = referenceDate
    }

    var scanStateText: String {
        switch phase {
        case .idle:
            "等待选择照片"
        case .awaitingContext:
            "等待补充食物信息"
        case .preparingImage:
            "正在优化照片"
        case .analyzing:
            "正在识别食物与营养"
        case .needsReview:
            if let result {
                "已识别 · 置信度 \(result.confidenceText)"
            } else {
                "等待检查结果"
            }
        case .saving:
            "正在保存饮食记录"
        case .saved:
            "已保存到饮食记录"
        case .failed:
            "识别未完成"
        }
    }

    var saveButtonTitle: String {
        phase == .saved ? "已保存" : "保存到饮食记录"
    }

    var isBusy: Bool {
        phase == .preparingImage || phase == .analyzing || phase == .saving
    }

    var remainingPhotoSlots: Int {
        max(0, maxPhotoCount - selectedPhotos.count)
    }

    /// 开始记录新的一餐：替换全部照片并清空描述和结果
    func selectPhotos(_ photos: [Data], referenceDate: Date = .now) {
        guard !photos.isEmpty else { return }

        cancelAnalysis()
        selectedPhotos = Array(photos.prefix(maxPhotoCount))
        photoRevision += 1
        preparedPhotos = []
        selectedMealPeriod = MealPeriod.inferred(for: referenceDate)
        eatenAt = referenceDate
        userFoodContext = ""
        userNote = ""
        result = nil
        phase = .awaitingContext
    }

    /// 为同一餐追加照片，保留已填写的描述；已有的识别结果作废，需要重新识别
    func addPhotos(_ photos: [Data]) {
        let accepted = photos.prefix(remainingPhotoSlots)
        guard !accepted.isEmpty else { return }

        cancelAnalysis()
        selectedPhotos.append(contentsOf: accepted)
        photoRevision += 1
        invalidateAnalysis()
    }

    func removePhoto(at index: Int) {
        guard selectedPhotos.indices.contains(index) else { return }

        cancelAnalysis()
        selectedPhotos.remove(at: index)
        photoRevision += 1
        if selectedPhotos.isEmpty {
            preparedPhotos = []
            result = nil
            phase = .idle
        } else {
            invalidateAnalysis()
        }
    }

    private func invalidateAnalysis() {
        preparedPhotos = []
        result = nil
        phase = .awaitingContext
    }

    func startAnalysis(skipDescription: Bool = false) {
        if skipDescription {
            userFoodContext = ""
        }

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.analyze()
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    func save() async {
        guard let result else { return }
        guard !selectedPhotos.isEmpty else {
            phase = .failed("找不到待保存的餐食照片。")
            return
        }

        phase = .saving
        let mealID = UUID()
        var savedFilename: String?

        do {
            let photos = try await preparePhotosIfNeeded()
            savedFilename = try await photoStore.saveJPEGs(photos, mealID: mealID)
            let items = result.items.map { item in
                MealFoodItem(
                    id: item.id,
                    name: item.name,
                    portionDescription: item.portionDescription,
                    estimatedGrams: item.estimatedGrams,
                    caloriesKcal: item.caloriesKcal,
                    carbohydratesGrams: item.carbohydratesGrams,
                    proteinGrams: item.proteinGrams,
                    fatGrams: item.fatGrams,
                    fiberGrams: item.fiberGrams,
                    confidence: item.confidence,
                    evidence: item.evidence,
                    uncertainties: item.uncertainties,
                    isUserConfirmed: true
                )
            }
            let meal = MealRecord(
                id: mealID,
                eatenAt: eatenAt,
                mealPeriod: selectedMealPeriod,
                title: result.name,
                source: .aiPhoto,
                userFoodContext: userFoodContext.normalizedOptional,
                note: userNote.normalizedOptional,
                caloriesKcal: result.caloriesKcal,
                carbohydratesGrams: result.carbohydratesGrams,
                proteinGrams: result.proteinGrams,
                fatGrams: result.fatGrams,
                fiberGrams: result.fiberGrams,
                photoFilename: savedFilename,
                aiProvider: result.provider,
                aiModel: result.model,
                promptVersion: result.promptVersion,
                analysisConfidence: result.confidence,
                glucoseImpact: result.effectiveGlucoseImpact,
                score: result.effectiveScore,
                suggestions: result.suggestions,
                followUpQuestions: result.followUpQuestions,
                uncertainties: result.uncertainties,
                items: items
            )
            try await mealRepository.save(meal)
            phase = .saved
        } catch is CancellationError {
            if let savedFilename {
                await photoStore.delete(filename: savedFilename)
            }
            phase = .needsReview
        } catch {
            if let savedFilename {
                await photoStore.delete(filename: savedFilename)
            }
            phase = .failed(error.localizedDescription)
        }
    }

    private func preparePhotosIfNeeded() async throws -> [Data] {
        if preparedPhotos.count == selectedPhotos.count {
            return preparedPhotos
        }

        let revision = photoRevision
        var prepared: [Data] = []
        for photo in selectedPhotos {
            prepared.append(try await FoodImageProcessor.prepareForAnalysis(photo))
            try Task.checkCancellation()
        }
        // 压缩期间照片被增删时不写回缓存，避免与当前照片错位
        if revision == photoRevision {
            preparedPhotos = prepared
        }
        return prepared
    }

    private func analyze() async {
        guard !selectedPhotos.isEmpty else {
            phase = .failed("请先拍照或从图库选择照片。")
            return
        }

        do {
            phase = .preparingImage
            let prepared = try await preparePhotosIfNeeded()
            phase = .analyzing
            let analysis = try await analysisService.analyze(
                images: prepared,
                userFoodContext: userFoodContext.normalizedOptional,
                mealPeriod: selectedMealPeriod
            )
            // 识别期间追加或删除了照片时，旧结果不再对应当前照片
            try Task.checkCancellation()
            result = analysis
            phase = .needsReview
        } catch is CancellationError {
            phase = .awaitingContext
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

enum FoodScanPhase: Equatable {
    case idle
    case awaitingContext
    case preparingImage
    case analyzing
    case needsReview
    case saving
    case saved
    case failed(String)
}

private extension String {
    var normalizedOptional: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
