//
//  AppDependencies.swift
//  GlucoMoment
//

import Foundation
import SwiftData

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let glucoseRepository: any GlucoseRepository
    let mealRepository: any MealRepository
    let foodAnalysisService: any FoodAnalysisService
    let foodAnalysisSettings: FoodAnalysisSettings
    let foodAnalysisCredentialStore: any FoodAnalysisCredentialStoring
    let mealPhotoStore: any MealPhotoStoring

    static func live() throws -> AppDependencies {
        let modelContainer = try ModelContainerFactory.makeLive()
        let settings = FoodAnalysisSettings()
        let credentialStore = KeychainFoodAnalysisCredentialStore()
        return AppDependencies(
            modelContainer: modelContainer,
            glucoseRepository: SwiftDataGlucoseRepository(modelContainer: modelContainer),
            mealRepository: SwiftDataMealRepository(modelContainer: modelContainer),
            foodAnalysisService: FoodAnalysisConfiguration.makeService(
                settings: settings,
                credentialStore: credentialStore
            ),
            foodAnalysisSettings: settings,
            foodAnalysisCredentialStore: credentialStore,
            mealPhotoStore: LocalMealPhotoStore()
        )
    }

    static func preview() -> AppDependencies {
        do {
            let modelContainer = try ModelContainerFactory.makeInMemory()
            let repository = SwiftDataGlucoseRepository(modelContainer: modelContainer)
            for reading in DemoDataProvider.historicalReadings {
                try repository.save(reading)
            }
            let settings = FoodAnalysisSettings(mode: .demo)
            let credentialStore = InMemoryFoodAnalysisCredentialStore()
            return AppDependencies(
                modelContainer: modelContainer,
                glucoseRepository: repository,
                mealRepository: SwiftDataMealRepository(modelContainer: modelContainer),
                foodAnalysisService: FoodAnalysisConfiguration.makeService(
                    settings: settings,
                    credentialStore: credentialStore
                ),
                foodAnalysisSettings: settings,
                foodAnalysisCredentialStore: credentialStore,
                mealPhotoStore: InMemoryMealPhotoStore()
            )
        } catch {
            preconditionFailure("无法创建 Preview 数据容器：\(error.localizedDescription)")
        }
    }
}
