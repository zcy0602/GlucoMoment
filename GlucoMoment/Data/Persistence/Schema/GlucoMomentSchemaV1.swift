//
//  GlucoMomentSchemaV1.swift
//  GlucoMoment
//

import SwiftData

enum GlucoMomentSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [GlucoseSampleEntity.self]
    }
}
