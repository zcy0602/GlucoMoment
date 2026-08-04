//
//  ModelContainerFactory.swift
//  GlucoMoment
//

import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema(versionedSchema: GlucoMomentSchemaV1.self)

    static func makeLive() throws -> ModelContainer {
        try make(isStoredInMemoryOnly: false)
    }

    static func makeInMemory() throws -> ModelContainer {
        try make(isStoredInMemoryOnly: true)
    }

    private static func make(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let configurationName = isStoredInMemoryOnly
            ? "GlucoMoment-InMemory-\(UUID().uuidString)"
            : "GlucoMoment"
        let configuration = ModelConfiguration(
            configurationName,
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: GlucoMomentMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
