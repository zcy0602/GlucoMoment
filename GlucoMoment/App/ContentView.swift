//
//  ContentView.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tab.destination
                }
                .tabItem { tab.label }
                .tag(tab)
            }
        }
        .tint(Color.brandTeal)
    }
}

#Preview {
    ContentView()
}
