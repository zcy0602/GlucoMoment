//
//  GlucoMomentMigrationPlan.swift
//  GlucoMoment
//

import SwiftData

enum GlucoMomentMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [GlucoMomentSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
