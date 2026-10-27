//
//  MealFoodItemMeasurementEntity.swift
//  GlucoMoment
//

import Foundation
import SwiftData

/// LiDAR 测量摘要，与食物条目一一对应。
///
/// 和 `MealAnalysisSnapshotEntity` 一样作为 V5 新增实体单独保存，
/// 避免修改已发布的 `MealFoodItemEntity` 结构。
@Model
final class MealFoodItemMeasurementEntity {
  #Unique<MealFoodItemMeasurementEntity>([\.foodItemID])

  var foodItemID: UUID
  var mealID: UUID
  var methodRawValue: String
  var volumeMilliliters: Double
  var volumeMinMilliliters: Double
  var volumeMaxMilliliters: Double
  var footprintAreaSquareCentimeters: Double
  var meanHeightCentimeters: Double
  var coverage: Double
  var containerTypeRawValue: String
  var densityGramsPerMilliliter: Double
  var densityMinGramsPerMilliliter: Double
  var densityMaxGramsPerMilliliter: Double
  var densitySourceRawValue: String
  var measuredGrams: Double
  var measuredGramsMin: Double
  var measuredGramsMax: Double
  var notesData: Data?

  init(foodItemID: UUID, mealID: UUID, measurement: FoodItemMeasurement) {
    self.foodItemID = foodItemID
    self.mealID = mealID
    methodRawValue = measurement.method.rawValue
    volumeMilliliters = measurement.volumeMilliliters
    volumeMinMilliliters = measurement.volumeMinMilliliters
    volumeMaxMilliliters = measurement.volumeMaxMilliliters
    footprintAreaSquareCentimeters = measurement.footprintAreaSquareCentimeters
    meanHeightCentimeters = measurement.meanHeightCentimeters
    coverage = measurement.coverage
    containerTypeRawValue = measurement.containerType.rawValue
    densityGramsPerMilliliter = measurement.densityGramsPerMilliliter
    densityMinGramsPerMilliliter = measurement.densityMinGramsPerMilliliter
    densityMaxGramsPerMilliliter = measurement.densityMaxGramsPerMilliliter
    densitySourceRawValue = measurement.densitySource.rawValue
    measuredGrams = measurement.measuredGrams
    measuredGramsMin = measurement.measuredGramsMin
    measuredGramsMax = measurement.measuredGramsMax
    notesData = measurement.notes.isEmpty ? nil : try? JSONEncoder().encode(measurement.notes)
  }

  var measurement: FoodItemMeasurement {
    FoodItemMeasurement(
      method: FoodMeasurementMethod(rawValue: methodRawValue) ?? .lidarMeasured,
      volumeMilliliters: volumeMilliliters,
      volumeMinMilliliters: volumeMinMilliliters,
      volumeMaxMilliliters: volumeMaxMilliliters,
      footprintAreaSquareCentimeters: footprintAreaSquareCentimeters,
      meanHeightCentimeters: meanHeightCentimeters,
      coverage: coverage,
      containerType: FoodContainerType(rawValue: containerTypeRawValue) ?? .noContainer,
      densityGramsPerMilliliter: densityGramsPerMilliliter,
      densityMinGramsPerMilliliter: densityMinGramsPerMilliliter,
      densityMaxGramsPerMilliliter: densityMaxGramsPerMilliliter,
      densitySource: FoodDensitySource(rawValue: densitySourceRawValue) ?? .categoryDefault,
      measuredGrams: measuredGrams,
      measuredGramsMin: measuredGramsMin,
      measuredGramsMax: measuredGramsMax,
      notes: notesData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    )
  }
}
