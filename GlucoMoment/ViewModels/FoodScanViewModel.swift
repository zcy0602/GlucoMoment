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
    private var preparedPhotoData: Data?

    var phase: FoodScanPhase = .idle
    var selectedPhotoData: Data?
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

    func selectPhoto(_ data: Data, referenceDate: Date = .now) {
        cancelAnalysis()
        selectedPhotoData = data
        preparedPhotoData = nil
        selectedMealPeriod = MealPeriod.inferred(for: referenceDate)
        eatenAt = referenceDate
        userFoodContext = ""
        userNote = ""
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
        guard let photoData = preparedPhotoData ?? selectedPhotoData else {
            phase = .failed("找不到待保存的餐食照片。")
            return
        }

        phase = .saving
        let mealID = UUID()
        var savedFilename: String?

        do {
            let preparedData: Data
            if let preparedPhotoData {
                preparedData = preparedPhotoData
            } else {
                preparedData = try await FoodImageProcessor.prepareForAnalysis(photoData)
                self.preparedPhotoData = preparedData
            }

            savedFilename = try await photoStore.saveJPEG(preparedData, mealID: mealID)
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

    private func analyze() async {
        guard let selectedPhotoData else {
            phase = .failed("请先拍照或从图库选择照片。")
            return
        }

        do {
            phase = .preparingImage
            let prepared = try await FoodImageProcessor.prepareForAnalysis(selectedPhotoData)
            try Task.checkCancellation()
            preparedPhotoData = prepared
            phase = .analyzing
            result = try await analysisService.analyze(
                imageData: prepared,
                userFoodContext: userFoodContext.normalizedOptional,
                mealPeriod: selectedMealPeriod
            )
            try Task.checkCancellation()
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
