//
//  FoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

nonisolated protocol FoodAnalysisService: Sendable {
    func analyze(
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult
}

nonisolated enum FoodAnalysisError: LocalizedError, Sendable {
    case invalidEndpoint
    case missingCredential
    case invalidImage
    case invalidResponse
    case networkUnavailable
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "食物识别服务地址无效。"
        case .missingCredential:
            "尚未配置阿里云 API Key，请前往设置。"
        case .invalidImage:
            "照片无法处理，请重新选择。"
        case .invalidResponse:
            "识别服务返回了无法读取的结果，请重试。"
        case .networkUnavailable:
            "网络连接不可用，请检查网络后重试。"
        case .requestFailed(let statusCode, let message):
            message ?? "识别请求失败（\(statusCode)）。"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .requestFailed(let statusCode, _):
            statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .networkUnavailable:
            true
        case .invalidEndpoint, .missingCredential, .invalidImage, .invalidResponse:
            false
        }
    }
}
