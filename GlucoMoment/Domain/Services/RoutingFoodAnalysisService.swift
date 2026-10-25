//
//  RoutingFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

actor RoutingFoodAnalysisService: FoodAnalysisService {
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
        case .directAPI:
            guard let apiConfiguration = configuration.directAPI else {
                throw FoodAnalysisError.incompleteConfiguration
            }
            guard let apiKey = try await credentialStore.apiKey(for: apiConfiguration.provider),
                  !apiKey.isEmpty else {
                throw FoodAnalysisError.missingCredential
            }
            return try await OpenAICompatibleFoodAnalysisService(
                apiKey: apiKey,
                configuration: apiConfiguration
            ).analyze(
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
}
