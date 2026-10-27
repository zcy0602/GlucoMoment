//
//  GlucoMomentMigrationPlan.swift
//  GlucoMoment
//

import SwiftData

enum GlucoMomentMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            GlucoMomentSchemaV1.self,
            GlucoMomentSchemaV2.self,
            GlucoMomentSchemaV3.self,
            GlucoMomentSchemaV4.self,
            GlucoMomentSchemaV5.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: GlucoMomentSchemaV1.self,
                toVersion: GlucoMomentSchemaV2.self
            ),
            .lightweight(
                fromVersion: GlucoMomentSchemaV2.self,
                toVersion: GlucoMomentSchemaV3.self
            ),
            .lightweight(
                fromVersion: GlucoMomentSchemaV3.self,
                toVersion: GlucoMomentSchemaV4.self
            ),
            .lightweight(
                fromVersion: GlucoMomentSchemaV4.self,
                toVersion: GlucoMomentSchemaV5.self
            )
        ]
    }
}
