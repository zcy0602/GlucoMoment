//
//  MealRepository.swift
//  GlucoMoment
//

import Foundation

@MainActor
protocol MealRepository: AnyObject {
    func meals(in interval: DateInterval, period: MealPeriod?) throws -> [MealRecord]
    func save(_ meal: MealRecord) throws
    func delete(id: UUID) throws
}
