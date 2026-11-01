//
//  RootTabView.swift
//  GlucoMoment
//

import SwiftData
import SwiftUI

/// 新旧界面切换的开关。默认使用新版；也可以用启动参数 `-GlucoMoment.UI.Redesign NO` 临时切回旧版。
/// 旧版只在 Debug 包里能切换，Release 包一律用新版，设置页也不显示开关
enum InterfacePreference {
    static let redesignKey = "GlucoMoment.UI.Redesign"

    static var allowsLegacyDesign: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// 新版界面的三个标签页
enum RootTab: Hashable {
    case glucose
    case meals
    case review
}

/// 新版界面的根视图：血糖 / 饮食 / 复盘。血糖和饮食各管各的记录，复盘把两者连起来看。
/// 默认打开「饮食」，拍照识别是最先要看到的功能。设置在每页右上角，与「健康」App 的个人资料入口一致
struct RootTabView: View {
    let dependencies: AppDependencies
    let healthDataRevision: Int

    @State private var selection: RootTab = .meals

    var body: some View {
        TabView(selection: $selection) {
            Tab("血糖", systemImage: "drop", value: RootTab.glucose) {
                NavigationStack {
                    GlucoseView(
                        dependencies: dependencies,
                        healthDataRevision: healthDataRevision
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

            Tab("复盘", systemImage: "chart.dots.scatter", value: RootTab.review) {
                NavigationStack {
                    ReviewView(
                        dependencies: dependencies,
                        healthDataRevision: healthDataRevision
                    )
                }
            }
        }
        .tint(Color.brandTeal)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    RootTabView(dependencies: dependencies, healthDataRevision: 0)
        .modelContainer(dependencies.modelContainer)
}
