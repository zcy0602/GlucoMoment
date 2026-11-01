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
    @Environment(\.scenePhase) private var scenePhase
    /// 新版界面开关，在两版的设置页里都能切换（仅 Debug 包）
    @AppStorage(InterfacePreference.redesignKey) private var usesRedesign = true

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _healthKitCoordinator = State(initialValue: dependencies.healthKitCoordinator)
    }

    var body: some View {
        Group {
            if usesRedesign || !InterfacePreference.allowsLegacyDesign {
                RootTabView(
                    dependencies: dependencies,
                    healthDataRevision: healthKitCoordinator.dataRevision
                )
            } else {
                legacyTabs
            }
        }
        .task { await healthKitCoordinator.handleLaunch() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await healthKitCoordinator.handleBecameActive() }
        }
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

    /// 旧版界面，保留用于对比
    private var legacyTabs: some View {
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
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    ContentView(dependencies: dependencies)
        .modelContainer(dependencies.modelContainer)
}
