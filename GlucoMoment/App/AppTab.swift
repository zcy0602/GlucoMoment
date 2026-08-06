//
//  AppTab.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case meals
    case trends
    case plan

    var id: String { rawValue }

    @ViewBuilder
    func destination(
        dependencies: AppDependencies,
        healthDataRevision: Int
    ) -> some View {
        switch self {
        case .today:
            TodayDashboardView(
                repository: dependencies.glucoseRepository,
                healthDataRevision: healthDataRevision
            )
        case .meals:
            MealLogDemoView(
                repository: dependencies.mealRepository,
                analysisService: dependencies.foodAnalysisService,
                photoStore: dependencies.mealPhotoStore,
                healthDataRevision: healthDataRevision
            )
        case .trends:
            GlucoseTrendDemoView(
                repository: dependencies.glucoseRepository,
                healthDataRevision: healthDataRevision
            )
        case .plan:
            CarePlanDemoView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .today:
            Label("今日", systemImage: "sun.max")
        case .meals:
            Label("饮食", systemImage: "fork.knife")
        case .trends:
            Label("趋势", systemImage: "chart.xyaxis.line")
        case .plan:
            Label("方案", systemImage: "checklist")
        }
    }
}
