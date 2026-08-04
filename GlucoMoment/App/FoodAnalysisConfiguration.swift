//
//  FoodAnalysisConfiguration.swift
//  GlucoMoment
//

import Foundation

enum FoodAnalysisConfiguration {
    static func makeService(
        settings: FoodAnalysisSettings,
        credentialStore: any FoodAnalysisCredentialStoring
    ) -> any FoodAnalysisService {
        RoutingFoodAnalysisService(
            configurationProvider: { settings.runtimeConfiguration },
            credentialStore: credentialStore,
            installationIdentifier: InstallationIdentifier.current
        )
    }
}

private enum InstallationIdentifier {
    private static let key = "GlucoMoment.InstallationIdentifier"

    static var current: String {
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }

        let identifier = UUID().uuidString
        UserDefaults.standard.set(identifier, forKey: key)
        return identifier
    }
}
