//
//  GlucoMomentSchemaV2.swift
//  GlucoMoment
//

import SwiftData

enum GlucoMomentSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            GlucoseSampleEntity.self,
            MealRecordEntity.self,
            MealFoodItemEntity.self
        ]
    }
}
