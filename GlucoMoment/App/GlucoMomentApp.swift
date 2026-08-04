//
//  GlucoMomentApp.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftData
import SwiftUI

@main
struct GlucoMomentApp: App {
    private let dependenciesResult: Result<AppDependencies, any Error>

    init() {
        dependenciesResult = Result { try AppDependencies.live() }
    }

    var body: some Scene {
        WindowGroup {
            switch dependenciesResult {
            case .success(let dependencies):
                ContentView(dependencies: dependencies)
                    .modelContainer(dependencies.modelContainer)
            case .failure(let error):
                PersistenceUnavailableView(error: error)
            }
        }
    }
}
