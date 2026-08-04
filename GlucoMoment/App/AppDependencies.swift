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

    static func live() throws -> AppDependencies {
        let modelContainer = try ModelContainerFactory.makeLive()
        return AppDependencies(
            modelContainer: modelContainer,
            glucoseRepository: SwiftDataGlucoseRepository(modelContainer: modelContainer)
        )
    }

    static func preview() -> AppDependencies {
        do {
            let modelContainer = try ModelContainerFactory.makeInMemory()
            let repository = SwiftDataGlucoseRepository(modelContainer: modelContainer)
            for reading in DemoDataProvider.historicalReadings {
                try repository.save(reading)
            }
            return AppDependencies(modelContainer: modelContainer, glucoseRepository: repository)
        } catch {
            preconditionFailure("无法创建 Preview 数据容器：\(error.localizedDescription)")
        }
    }
}
