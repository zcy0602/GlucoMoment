//
//  RoutingFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

actor RoutingFoodAnalysisService: FoodAnalysisService, MealReviewService {
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
        images: [Data],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        try await resolveService().analyze(
            images: images,
            userFoodContext: userFoodContext,
            mealPeriod: mealPeriod
        )
    }

    func correct(_ request: FoodCorrectionRequest) async throws -> FoodCorrectionOutcome {
        try await resolveService().correct(request)
    }

    func review(_ payload: MealReviewPayload) async throws -> MealReviewDraft {
        try await resolveService().review(payload)
    }

    /// 每次调用都按当前设置选择服务，模式修改立即生效
    private func resolveService() async throws -> any FoodAnalysisService & MealReviewService {
        let configuration = await configurationProvider()
        switch configuration.mode {
        case .demo:
            return DemoFoodAnalysisService()
        case .directAPI:
            guard let apiConfiguration = configuration.directAPI else {
                throw FoodAnalysisError.incompleteConfiguration
            }
            guard let apiKey = try await credentialStore.apiKey(for: apiConfiguration.provider),
                  !apiKey.isEmpty else {
                throw FoodAnalysisError.missingCredential
            }
            return OpenAICompatibleFoodAnalysisService(
                apiKey: apiKey,
                configuration: apiConfiguration
            )
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
