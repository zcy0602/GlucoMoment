//
//  RoutingFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

actor RoutingFoodAnalysisService: FoodAnalysisService, MeasuredFoodAnalysisService {
    private let configurationProvider: @MainActor @Sendable () -> FoodAnalysisRuntimeConfiguration
    private let credentialStore: any FoodAnalysisCredentialStoring
    private let installationIdentifier: String

    init(
        configurationProvider: @escaping @MainActor @Sendable () -> FoodAnalysisRuntimeConfiguration,
        credentialStore: any FoodAnalysisCredentialStoring,
        installationIdentifier: String
    ) {
        self.configurationProvider = configurationProvider
        self.credentialStore = credentialStore
        self.installationIdentifier = installationIdentifier
    }

    func analyze(
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        let configuration = await configurationProvider()
        switch configuration.mode {
        case .demo:
            return try await DemoFoodAnalysisService().analyze(
                imageData: imageData,
                userFoodContext: userFoodContext,
                mealPeriod: mealPeriod
            )
        case .directQwen:
            guard let apiKey = try await credentialStore.apiKey(), !apiKey.isEmpty else {
                throw FoodAnalysisError.missingCredential
            }
            return try await QwenFoodAnalysisService(apiKey: apiKey).analyze(
                imageData: imageData,
                userFoodContext: userFoodContext,
                mealPeriod: mealPeriod
            )
        case .proxy:
            guard let endpoint = configuration.proxyEndpoint else {
                throw FoodAnalysisError.invalidEndpoint
            }
            return try await RemoteFoodAnalysisService(
                endpoint: endpoint,
                installationIdentifier: installationIdentifier
            ).analyze(
                imageData: imageData,
                userFoodContext: userFoodContext,
                mealPeriod: mealPeriod
            )
        }
    }

    func detectFoods(
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodDetectionResult {
        try await measuredService().detectFoods(
            imageData: imageData,
            userFoodContext: userFoodContext,
            mealPeriod: mealPeriod
        )
    }

    func estimateNutrition(
        imageData: Data,
        detection: FoodDetectionResult,
        measurements: [FoodMeasuredItem],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        try await measuredService().estimateNutrition(
            imageData: imageData,
            detection: detection,
            measurements: measurements,
            userFoodContext: userFoodContext,
            mealPeriod: mealPeriod
        )
    }

    /// 按当前模式创建两段式服务；每次调用重新读取配置，与 `analyze` 行为一致。
    private func measuredService() async throws -> any MeasuredFoodAnalysisService {
        let configuration = await configurationProvider()
        switch configuration.mode {
        case .demo:
            return DemoFoodAnalysisService()
        case .directQwen:
            guard let apiKey = try await credentialStore.apiKey(), !apiKey.isEmpty else {
                throw FoodAnalysisError.missingCredential
            }
            return QwenFoodAnalysisService(apiKey: apiKey)
        case .proxy:
            guard let endpoint = configuration.proxyEndpoint else {
                throw FoodAnalysisError.invalidEndpoint
            }
            return RemoteFoodAnalysisService(
                endpoint: endpoint,
                installationIdentifier: installationIdentifier
            )
        }
    }
}
