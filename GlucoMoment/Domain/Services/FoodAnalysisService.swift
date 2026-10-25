//
//  FoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

nonisolated protocol FoodAnalysisService: Sendable {
    /// `images` 为同一餐按拍摄顺序排列的 1～`maxImageCount` 张照片，在一次请求中交给模型综合估算
    func analyze(
        images: [Data],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult
}

nonisolated enum FoodAnalysisImageLimit {
    /// 须与代理 `core.ts` 的 `MAX_IMAGE_COUNT` 保持一致
    static let maxImageCount = 6
}

nonisolated enum FoodAnalysisError: LocalizedError, Sendable {
    case invalidEndpoint
    case missingCredential
    case incompleteConfiguration
    case visionUnsupported(model: String)
    case invalidImage
    case invalidResponse
    case networkUnavailable
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "食物识别服务地址无效。"
        case .missingCredential:
            "尚未配置 API Key，请前往设置。"
        case .incompleteConfiguration:
            "请在设置中填写有效的 HTTPS API 地址和模型名称。"
        case .visionUnsupported(let model):
            "\(model) 已连通，但没有正确识别测试图片，可能不支持图片输入。请换用视觉模型。"
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
        case .invalidEndpoint, .missingCredential, .incompleteConfiguration,
             .visionUnsupported, .invalidImage, .invalidResponse:
            false
        }
    }
}
