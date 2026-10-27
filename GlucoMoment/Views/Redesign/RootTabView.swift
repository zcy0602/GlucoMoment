//
//  RootTabView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 新旧界面切换的开关。默认使用新版；也可以用启动参数 `-GlucoMoment.UI.Redesign NO` 临时切回旧版
enum InterfacePreference {
    static let redesignKey = "GlucoMoment.UI.Redesign"
}

/// 新版界面的三个标签页
enum RootTab: Hashable {
    case today
    case meals
    case trends
}

/// 新版界面的根视图：今天 / 饮食 / 趋势。设置从「今天」右上角进入，与「健康」App 的个人资料入口一致
struct RootTabView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var selection: RootTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("今天", systemImage: "sun.max", value: RootTab.today) {
                NavigationStack {
                    TodayView(
                        dependencies: dependencies,
                        healthDataRevision: healthDataRevision,
                        onShowTab: { selection = $0 }
                    )
                }
            }

            Tab("饮食", systemImage: "fork.knife", value: RootTab.meals) {
                NavigationStack {
                    MealsDiaryView(
                        dependencies: dependencies,
                        healthDataRevision: healthDataRevision
                    )
                }
            }

            Tab("趋势", systemImage: "chart.xyaxis.line", value: RootTab.trends) {
                NavigationStack {
                    TrendsView(
                        dependencies: dependencies,
                        healthDataRevision: healthDataRevision
                    )
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.brandTeal)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    RootTabView(dependencies: dependencies, healthDataRevision: 0)
        .modelContainer(dependencies.modelContainer)
}
