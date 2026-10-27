//
//  GlucoMomentSchemaV5.swift
//  GlucoMoment
//

import SwiftData

/// V5 新增 LiDAR 测量摘要实体。
enum GlucoMomentSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            GlucoseSampleEntity.self,
            MealRecordEntity.self,
            MealFoodItemEntity.self,
            MealAnalysisSnapshotEntity.self,
            HealthKitSyncStateEntity.self,
            MealFoodItemMeasurementEntity.self
        ]
    }
}
