//
//  GlucoMomentSchemaV4.swift
//  GlucoMoment
//

import SwiftData

enum GlucoMomentSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            GlucoseSampleEntity.self,
            MealRecordEntity.self,
            MealFoodItemEntity.self,
            MealAnalysisSnapshotEntity.self,
            HealthKitSyncStateEntity.self
        ]
    }
}
