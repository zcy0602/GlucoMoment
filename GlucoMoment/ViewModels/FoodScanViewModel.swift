//
//  FoodScanViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/7/6.
//

import Foundation
import Observation
import simd

@MainActor
@Observable
final class FoodScanViewModel {
    let title = "拍照识别"

    private let analysisService: any FoodAnalysisService
    private let mealRepository: any MealRepository
    private let photoStore: any MealPhotoStoring
    private var analysisTask: Task<Void, Never>?
    private var measurementTask: Task<Void, Never>?
    private var preparedPhotoData: Data?

    var phase: FoodScanPhase = .idle
    var selectedPhotoData: Data?
    var userFoodContext = ""
    var result: FoodRecognitionResult?
    var selectedMealPeriod: MealPeriod
    var eatenAt = Date.now
    var userNote = ""

    // MARK: LiDAR 两段式识别状态

    private(set) var depthCapture: FoodDepthCapture?
    private(set) var detection: FoodDetectionResult?
    private(set) var measurementOutput: FoodMeasurementOutput?
    private(set) var segmentationMethod: FoodSegmentationMethod?
    private(set) var adjustments = FoodMeasurementAdjustments()
    private(set) var isRecomputingMeasurement = false
    var selectedItemIndex: Int?

    @ObservationIgnored private var heightMap: PlaneHeightMap?
    @ObservationIgnored private var cellImagePoints: [SIMD2<Float>?]?
    @ObservationIgnored private var masks: [Int: FoodMaskRaster]?
    @ObservationIgnored private var segmentation: FoodSegmentationService?

    init(
        analysisService: any FoodAnalysisService,
        mealRepository: any MealRepository,
        photoStore: any MealPhotoStoring,
        initialMealPeriod: MealPeriod = .lunch
    ) {
        self.analysisService = analysisService
        self.mealRepository = mealRepository
        self.photoStore = photoStore
        selectedMealPeriod = initialMealPeriod
    }

    var scanStateText: String {
        switch phase {
        case .idle:
            "等待选择照片"
        case .awaitingContext:
            isMeasuredFlow ? "LiDAR 扫描完成 · 等待补充食物信息" : "等待补充食物信息"
        case .preparingImage:
            "正在优化照片"
        case .detecting:
            "正在定位食物并融合深度数据"
        case .segmenting:
            "正在分割菜品"
        case .reviewingMeasurement:
            "请检查实测份量"
        case .estimating:
            "正在结合实测份量估算营养"
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
        switch phase {
        case .preparingImage, .detecting, .segmenting, .estimating, .analyzing, .saving:
            true
        case .idle, .awaitingContext, .reviewingMeasurement, .needsReview, .saved, .failed:
            false
        }
    }

    /// 当前照片来自 LiDAR 扫描，且识别服务支持两段式识别。
    var isMeasuredFlow: Bool {
        depthCapture != nil && measuredService != nil
    }

    private var measuredService: (any MeasuredFoodAnalysisService)? {
        analysisService as? any MeasuredFoodAnalysisService
    }

    func selectPhoto(_ data: Data) {
        cancelAnalysis()
        clearMeasurementState()
        depthCapture = nil
        selectedPhotoData = data
        preparedPhotoData = nil
        userFoodContext = ""
        userNote = ""
        result = nil
        phase = .awaitingContext
    }

    /// 使用 LiDAR 扫描结果：最佳俯视帧作为识别照片，深度数据用于测量份量。
    func selectDepthCapture(_ capture: FoodDepthCapture) {
        selectPhoto(capture.orientedImageData)
        depthCapture = capture
    }

    func startAnalysis(skipDescription: Bool = false) {
        if skipDescription {
            userFoodContext = ""
        }

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            if self.isMeasuredFlow {
                await self.analyzeMeasured()
            } else {
                await self.analyze()
            }
        }
    }

    /// LiDAR 流程失败时，改用原有的单张照片识别。
    func fallBackToPhotoAnalysis() {
        cancelAnalysis()
        clearMeasurementState()
        depthCapture = nil
        startAnalysis()
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        measurementTask?.cancel()
        measurementTask = nil
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
                    isUserConfirmed: true,
                    measurement: item.measurement
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
                glucoseImpact: result.glucoseImpact,
                score: result.score,
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

    // MARK: - LiDAR 两段式识别

    /// ①定位食物（同时在后台融合深度）→ 分割 → 本地测量，随后进入测量审核。
    private func analyzeMeasured() async {
        guard let capture = depthCapture, let service = measuredService else {
            await analyze()
            return
        }

        clearMeasurementState()
        result = nil

        do {
            phase = .preparingImage
            let prepared = try await FoodImageProcessor.prepareForAnalysis(capture.orientedImageData)
            try Task.checkCancellation()
            preparedPhotoData = prepared

            let geometryTask = Task.detached(priority: .userInitiated) {
                let map = FoodDepthCaptureProcessor.makeHeightMap(from: capture)
                return (map, FoodDepthCaptureProcessor.orientedImagePoints(for: map, capture: capture))
            }

            phase = .detecting
            let detection = try await service.detectFoods(
                imageData: prepared,
                userFoodContext: userFoodContext.normalizedOptional,
                mealPeriod: selectedMealPeriod
            )
            let geometry = await geometryTask.value
            try Task.checkCancellation()

            phase = .segmenting
            let segmentation = await FoodSegmentationService.make(
                imageData: prepared,
                imageSize: capture.orientedImageSize
            )
            let masks = try await segmentation.segment(items: detection.items)
            try Task.checkCancellation()

            self.detection = detection
            self.heightMap = geometry.0
            self.cellImagePoints = geometry.1
            self.segmentation = segmentation
            self.segmentationMethod = segmentation.method
            self.masks = masks
            selectedItemIndex = detection.items.first?.index

            try await recomputeMeasurements()
            phase = .reviewingMeasurement
        } catch is CancellationError {
            phase = .awaitingContext
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// ②用户确认实测份量后，结合实测数据估算营养。
    func confirmMeasurements() {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.estimateMeasuredNutrition()
        }
    }

    private func estimateMeasuredNutrition() async {
        guard let service = measuredService,
              let detection,
              let measurementOutput,
              let preparedPhotoData else { return }

        // 等待正在进行的修正与重算完成，确保上传的是最新结果。
        await measurementTask?.value

        do {
            phase = .estimating
            result = try await service.estimateNutrition(
                imageData: preparedPhotoData,
                detection: detection,
                measurements: self.measurementOutput?.measurements ?? measurementOutput.measurements,
                userFoodContext: userFoodContext.normalizedOptional,
                mealPeriod: selectedMealPeriod
            )
            try Task.checkCancellation()
            phase = .needsReview
        } catch is CancellationError {
            phase = .reviewingMeasurement
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func containerType(for containerIndex: Int) -> FoodContainerType {
        adjustments.containerTypes[containerIndex]
            ?? detection?.container(index: containerIndex)?.type
            ?? .flatPlate
    }

    func setContainerType(_ type: FoodContainerType, for containerIndex: Int) {
        adjustments.containerTypes[containerIndex] = type
        scheduleRecompute()
    }

    func layerThickness(for itemIndex: Int) -> Double {
        if let thickness = adjustments.layerThicknessCentimeters[itemIndex] {
            return thickness
        }
        guard let range = detection?.item(index: itemIndex)?.layerThicknessCentimeters else { return 1 }
        return (range.lowerBound + range.upperBound) / 2
    }

    func setLayerThickness(_ centimeters: Double, for itemIndex: Int) {
        adjustments.layerThicknessCentimeters[itemIndex] = centimeters
        scheduleRecompute()
    }

    func measurement(for itemIndex: Int) -> FoodItemMeasurement? {
        measurementOutput?.measurements.first { $0.detection.index == itemIndex }?.measurement
    }

    /// 点按照片修正当前选中食物的区域（归一化坐标，左上角原点）。
    func refineSelectedItem(at point: SIMD2<Float>, include: Bool) {
        guard let segmentation, let itemIndex = selectedItemIndex else { return }
        let previous = measurementTask
        measurementTask = Task { [weak self] in
            await previous?.value
            do {
                let masks = try await segmentation.refine(itemIndex: itemIndex, at: point, include: include)
                guard let self else { return }
                self.masks = masks
                try await self.recomputeMeasurements()
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 点按照片选中该位置的食物。
    func selectItem(at point: SIMD2<Float>) {
        guard let label = measurementOutput?.overlay.label(at: point), label >= 0 else { return }
        selectedItemIndex = Int(label)
    }

    private func scheduleRecompute() {
        let previous = measurementTask
        measurementTask = Task { [weak self] in
            await previous?.value
            try? await self?.recomputeMeasurements()
        }
    }

    private func recomputeMeasurements() async throws {
        guard let heightMap, let cellImagePoints, let detection, let masks, let depthCapture else { return }
        let adjustments = adjustments
        let overlaySize = FoodMaskRaster.size(forImageSize: depthCapture.orientedImageSize, longSide: 192)

        isRecomputingMeasurement = true
        defer { isRecomputingMeasurement = false }

        let output = await Task.detached(priority: .userInitiated) {
            FoodMeasurementPipeline.run(
                heightMap: heightMap,
                cellImagePoints: cellImagePoints,
                detection: detection,
                masks: masks,
                adjustments: adjustments,
                overlaySize: overlaySize
            )
        }.value
        try Task.checkCancellation()
        measurementOutput = output
    }

    private func clearMeasurementState() {
        measurementTask?.cancel()
        measurementTask = nil
        detection = nil
        measurementOutput = nil
        segmentationMethod = nil
        adjustments = FoodMeasurementAdjustments()
        selectedItemIndex = nil
        heightMap = nil
        cellImagePoints = nil
        masks = nil
        segmentation = nil
    }
}

enum FoodScanPhase: Equatable {
    case idle
    case awaitingContext
    case preparingImage
    case detecting
    case segmenting
    case reviewingMeasurement
    case estimating
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
