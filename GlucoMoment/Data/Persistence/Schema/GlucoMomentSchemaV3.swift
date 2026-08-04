//
//  GlucoMomentSchemaV3.swift
//  GlucoMoment
//

import SwiftData

enum GlucoMomentSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            GlucoseSampleEntity.self,
            MealRecordEntity.self,
            MealFoodItemEntity.self,
            MealAnalysisSnapshotEntity.self
        ]
    }
}
