//
//  ContentView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies
    @State private var selectedTab: AppTab = .today
    @State private var healthKitCoordinator: HealthKitCoordinator

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _healthKitCoordinator = State(initialValue: dependencies.healthKitCoordinator)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tab.destination(
                        dependencies: dependencies,
                        healthDataRevision: healthKitCoordinator.dataRevision
                    )
                        
                }
                
                .tabItem { tab.label }
                .tag(tab)
            }
            
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color.brandTeal)
        .task { await healthKitCoordinator.handleLaunch() }
        .sheet(item: $healthKitCoordinator.presentedSheet) { sheet in
            switch sheet {
            case .introduction:
                HealthKitIntroductionView(coordinator: healthKitCoordinator)
            }
        }
        .alert("HealthKit 操作失败", isPresented: $healthKitCoordinator.isShowingError) {
        } message: {
            Text(healthKitCoordinator.errorMessage ?? "请稍后重试。")
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    ContentView(dependencies: dependencies)
        .modelContainer(dependencies.modelContainer)
}
