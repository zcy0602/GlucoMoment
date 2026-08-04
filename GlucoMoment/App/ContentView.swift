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

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tab.destination(dependencies: dependencies)
                }
                .tabItem { tab.label }
                .tag(tab)
            }
        }
        .tint(Color.brandTeal)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    ContentView(dependencies: dependencies)
        .modelContainer(dependencies.modelContainer)
}
