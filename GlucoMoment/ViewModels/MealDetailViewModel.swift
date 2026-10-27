//
//  MealDetailViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 新版餐食详情：读取照片和这一餐前后的血糖，计算餐后反应
@MainActor
@Observable
final class MealDetailViewModel {
    /// 用餐前后取多长时间的血糖：前 1 小时用于找基线和真实开始时间，后 3 小时覆盖餐后曲线
    static let lookbackSeconds: TimeInterval = 60 * 60
    static let lookaheadSeconds: TimeInterval = 3 * 60 * 60

    let meal: MealRecord
    private let glucoseRepository: any GlucoseRepository
    private let mealRepository: any MealRepository
    private let photoStore: any MealPhotoStoring

    private(set) var photos: [Data] = []
    private(set) var glucosePoints: [GlucosePoint] = []
    private(set) var response: MealGlucoseResponse?
    private(set) var errorMessage: String?

    init(
        meal: MealRecord,
        glucoseRepository: any GlucoseRepository,
        mealRepository: any MealRepository,
        photoStore: any MealPhotoStoring
    ) {
        self.meal = meal
        self.glucoseRepository = glucoseRepository
        self.mealRepository = mealRepository
        self.photoStore = photoStore
    }

    var canDelete: Bool {
        meal.source != .healthKit
    }

    func load() async {
        if let filename = meal.photoFilename {
            photos = await photoStore.allJPEGData(primaryFilename: filename)
        }

        let window = DateInterval(
            start: meal.eatenAt.addingTimeInterval(-Self.lookbackSeconds),
            end: meal.eatenAt.addingTimeInterval(Self.lookaheadSeconds)
        )
        do {
            glucosePoints = try glucoseRepository.readings(in: window)
                .map { GlucosePoint(time: $0.measuredAt, value: $0.value) }
        } catch {
            glucosePoints = []
        }
        response = MealGlucoseResponseCalculator.response(recordedStart: meal.eatenAt, points: glucosePoints)
    }

    /// 删除成功返回 true
    func delete() async -> Bool {
        do {
            try await mealRepository.delete(id: meal.id)
            return true
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
            return false
        }
    }
}
