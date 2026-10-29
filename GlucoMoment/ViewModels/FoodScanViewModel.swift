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
    /// 照片的拍摄时间；读不到或不合理时为 nil
    private(set) var photoCaptureDate: Date?
    /// 用户是否手动选过餐次；选过之后改用餐时间不再自动推断餐次
    private var hasPickedMealPeriod = false
    var userNote = ""
    /// 本餐的一句话修正记录，随复核页「完成」写回；换照片或重新识别后清空
    var correctionHistory: [FoodCorrectionTurn] = []

    /// 正在编辑的已保存餐食；为 nil 时是记录新的一餐
    private(set) var editingMeal: MealRecord?
    /// 编辑开始时的识别结果，用来判断有没有未保存的修改
    private var originalResult: FoodRecognitionResult?
    /// 编辑保存成功后的记录，供详情页刷新
    private(set) var savedMeal: MealRecord?

    /// 第一版修正只发文字；修正接口已支持附带照片，改为 true 即把本餐照片一并发送
    static let sendsPhotosWithCorrection = false

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

    /// 编辑一条已保存的餐食：直接进入结果页，照片沿用已保存的版本，不能重新识别
    convenience init(
        editing meal: MealRecord,
        photos: [Data],
        analysisService: any FoodAnalysisService,
        mealRepository: any MealRepository,
        photoStore: any MealPhotoStoring
    ) {
        self.init(
            analysisService: analysisService,
            mealRepository: mealRepository,
            photoStore: photoStore,
            referenceDate: meal.eatenAt
        )
        let result = FoodRecognitionResult(editing: meal)
        editingMeal = meal
        originalResult = result
        self.result = result
        selectedPhotos = photos
        selectedMealPeriod = meal.mealPeriod
        hasPickedMealPeriod = true
        userFoodContext = meal.userFoodContext ?? ""
        userNote = meal.note ?? ""
        phase = .needsReview
    }

    /// `eatenAt` 是否仍是照片的拍摄时间；用户改过时间后为 false
    var isEatenAtFromPhoto: Bool {
        photoCaptureDate != nil && photoCaptureDate == eatenAt
    }

    /// 用户手动选择餐次
    func pickMealPeriod(_ period: MealPeriod) {
        selectedMealPeriod = period
        hasPickedMealPeriod = true
    }

    /// 用户手动修改用餐时间；没手动选过餐次时，按新时间重新推断
    func changeEatenAt(_ date: Date) {
        eatenAt = date
        if !hasPickedMealPeriod {
            selectedMealPeriod = MealPeriod.inferred(for: date)
        }
    }

    var isEditingSavedMeal: Bool {
        editingMeal != nil
    }

    /// 编辑模式下是否改过内容；关闭前据此决定要不要确认
    var hasUnsavedEdits: Bool {
        guard let editingMeal else { return result != nil }
        return result != originalResult
            || eatenAt != editingMeal.eatenAt
            || selectedMealPeriod != editingMeal.mealPeriod
            || !correctionHistory.isEmpty
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

    /// 照片拍摄时间与选图时间相差在此范围内才采用，过早的照片多半是翻出来的旧图
    static let captureDateLookback: TimeInterval = 7 * 24 * 3_600
    /// 允许照片时间略晚于当前时间，容忍设备间的时钟误差
    static let captureDateFutureTolerance: TimeInterval = 5 * 60

    /// 开始记录新的一餐：替换全部照片并清空描述和结果。
    /// 用餐时间优先取最早一张照片的拍摄时间，读不到或不合理时用选图时间
    func selectPhotos(_ photos: [Data], referenceDate: Date = .now) {
        guard !photos.isEmpty else { return }

        cancelAnalysis()
        selectedPhotos = Array(photos.prefix(maxPhotoCount))
        photoRevision += 1
        preparedPhotos = []
        let captureDate = Self.plausibleCaptureDate(of: selectedPhotos, referenceDate: referenceDate)
        let mealDate = captureDate ?? referenceDate
        selectedMealPeriod = MealPeriod.inferred(for: mealDate)
        eatenAt = mealDate
        photoCaptureDate = captureDate
        hasPickedMealPeriod = false
        userFoodContext = ""
        userNote = ""
        result = nil
        correctionHistory = []
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
            correctionHistory = []
            phase = .idle
        } else {
            invalidateAnalysis()
        }
    }

    private static func plausibleCaptureDate(of photos: [Data], referenceDate: Date) -> Date? {
        let earliest = referenceDate.addingTimeInterval(-captureDateLookback)
        let latest = referenceDate.addingTimeInterval(captureDateFutureTolerance)
        return photos
            .compactMap(FoodImageProcessor.captureDate(of:))
            .filter { $0 >= earliest && $0 <= latest }
            .min()
            .map { min($0, referenceDate) }
    }

    private func invalidateAnalysis() {
        preparedPhotos = []
        result = nil
        correctionHistory = []
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

    /// 按一句话说明修正复核页的草稿；不直接改动 `result`，由复核页决定是否采用
    func correct(
        _ draft: FoodRecognitionResult,
        instruction: String,
        history: [FoodCorrectionTurn],
        mealPeriod: MealPeriod
    ) async throws -> FoodCorrectionOutcome {
        let images = Self.sendsPhotosWithCorrection ? try await preparePhotosIfNeeded() : []
        return try await analysisService.correct(
            FoodCorrectionRequest(
                current: draft,
                instruction: instruction,
                history: history,
                userFoodContext: userFoodContext.normalizedOptional,
                mealPeriod: mealPeriod,
                images: images
            )
        )
    }

    func save() async {
        guard let result else { return }
        if let editingMeal {
            await saveEdits(to: editingMeal, result: result)
            return
        }
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
            let items = Self.mealItems(from: result)
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
                suggestions: result.effectiveSuggestions,
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

    /// 就地更新已保存的餐食：沿用原 id、照片和识别来源，只替换内容
    private func saveEdits(to meal: MealRecord, result: FoodRecognitionResult) async {
        phase = .saving
        var updated = meal
        updated.eatenAt = eatenAt
        updated.mealPeriod = selectedMealPeriod
        updated.title = result.name
        updated.userFoodContext = userFoodContext.normalizedOptional
        updated.note = userNote.normalizedOptional
        updated.caloriesKcal = result.caloriesKcal
        updated.carbohydratesGrams = result.carbohydratesGrams
        updated.proteinGrams = result.proteinGrams
        updated.fatGrams = result.fatGrams
        updated.fiberGrams = result.fiberGrams
        // 条目缺少类别、无法按公式计算时，保留原来保存的分数，而不是写入占位值
        updated.score = result.stableScore?.score ?? meal.score
        updated.glucoseImpact = result.stableScore?.glucoseImpact ?? meal.glucoseImpact
        updated.suggestions = result.effectiveSuggestions
        updated.followUpQuestions = result.followUpQuestions
        updated.uncertainties = result.uncertainties
        updated.items = Self.mealItems(from: result)

        do {
            try await mealRepository.save(updated)
            editingMeal = updated
            originalResult = result
            correctionHistory = []
            savedMeal = updated
            phase = .saved
        } catch is CancellationError {
            phase = .needsReview
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func mealItems(from result: FoodRecognitionResult) -> [MealFoodItem] {
        result.items.map { item in
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
                foodCategory: item.foodCategory
            )
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
            correctionHistory = []
            phase = .needsReview
        } catch is CancellationError {
            phase = .awaitingContext
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private extension FoodRecognitionResult {
    /// 把已保存的餐食还原成可编辑的识别结果；缺失的字段用中性值占位，保存时不会写回
    init(editing meal: MealRecord) {
        self.init(
            name: meal.title,
            confidence: meal.analysisConfidence ?? 1,
            glucoseImpact: meal.glucoseImpact ?? "",
            score: meal.score ?? 0,
            items: meal.items.map { item in
                FoodRecognitionItem(
                    id: item.id,
                    name: item.name,
                    portionDescription: item.portionDescription,
                    estimatedGrams: item.estimatedGrams,
                    caloriesKcal: item.caloriesKcal,
                    carbohydratesGrams: item.carbohydratesGrams,
                    proteinGrams: item.proteinGrams,
                    fatGrams: item.fatGrams,
                    fiberGrams: item.fiberGrams,
                    confidence: item.confidence ?? 1,
                    evidence: item.evidence ?? "",
                    uncertainties: item.uncertainties,
                    foodCategory: item.foodCategory
                )
            },
            suggestions: meal.suggestions,
            followUpQuestions: meal.followUpQuestions,
            uncertainties: meal.uncertainties,
            provider: meal.aiProvider ?? "",
            model: meal.aiModel ?? "",
            promptVersion: meal.promptVersion ?? ""
        )
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
