//
//  MealAnalysisSnapshotEntity.swift
//  GlucoMoment
//

import Foundation
import SwiftData

/// The immutable AI Review payload saved alongside a meal record.
///
/// Keeping this in a V3-only entity lets existing V2 meal entities retain their
/// published schema while newly saved meals preserve the complete Review result.
@Model
final class MealAnalysisSnapshotEntity {
  #Unique<MealAnalysisSnapshotEntity>([\.mealID])

  var mealID: UUID
  var glucoseImpact: String?
  var score: Int?
  var suggestionsData: Data?
  var followUpQuestionsData: Data?
  var uncertaintiesData: Data?
  var itemDetailsData: Data?

  init(
    mealID: UUID,
    glucoseImpact: String?,
    score: Int?,
    suggestionsData: Data?,
    followUpQuestionsData: Data?,
    uncertaintiesData: Data?,
    itemDetailsData: Data?
  ) {
    self.mealID = mealID
    self.glucoseImpact = glucoseImpact
    self.score = score
    self.suggestionsData = suggestionsData
    self.followUpQuestionsData = followUpQuestionsData
    self.uncertaintiesData = uncertaintiesData
    self.itemDetailsData = itemDetailsData
  }
}
