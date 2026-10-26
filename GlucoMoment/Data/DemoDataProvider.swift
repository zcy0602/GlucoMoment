//
//  DemoDataProvider.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Foundation

enum DemoDataProvider {
    static var readings: [GlucoseReading] {
        let samples: [(hour: Int, minute: Int, value: Double)] = [
            (7, 0, 5.3),
            (9, 0, 7.1),
            (11, 0, 6.6),
            (13, 0, 10.8),
            (15, 0, 7.4),
            (17, 0, 5.8),
            (19, 0, 7.8),
            (21, 0, 6.2)
        ]

        return samples.map { sample in
            GlucoseReading(
                measuredAt: dateToday(hour: sample.hour, minute: sample.minute),
                value: sample.value,
                source: .manual
            )
        }
    }

    static var historicalReadings: [GlucoseReading] {
        let calendar = Calendar.current
        let previousDays = (1...29).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: .now) ?? .now
            let measuredAt = calendar.date(bySettingHour: 8 + dayOffset % 10, minute: 0, second: 0, of: date) ?? date
            let value = 4.8 + Double((dayOffset * 7) % 54) / 10
            return GlucoseReading(measuredAt: measuredAt, value: value, source: .manual)
        }

        return previousDays + readings
    }

    private static func dateToday(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    /// 饮食页按餐次显示的通用建议。文案只写《成人糖尿病食养指南（2023 年版）》里有原文依据的内容，
    /// 不写个人化的碳水份量或血糖条件；修改文案时同步核对 `guidelines`。
    static let mealGuidances: [MealPeriod: MealGuidance] = [
        .breakfast: MealGuidance(
            period: .breakfast,
            title: "早餐建议",
            text: "主食里搭配全谷物或杂豆，比如全麦面包、杂粮粥；再配鸡蛋、牛奶或豆浆，加一份蔬菜。",
            tags: ["全谷物", "有奶有豆", "餐餐有菜"],
            guidelines: [.wholeGrainShare, .dairyAndSoyDaily, .vegetablesEveryMeal]
        ),
        .lunch: MealGuidance(
            period: .lunch,
            title: "午餐建议",
            text: "先吃菜，最后吃主食；全谷物和杂豆最好占主食的 1/3 以上。饭后可以快走一会儿，运动前后留意血糖。",
            tags: ["先菜后主食", "杂粮主食", "餐后活动"],
            guidelines: [.vegetablesFirst, .wholeGrainShare, .activityAfterMeals]
        ),
        .dinner: MealGuidance(
            period: .dinner,
            title: "晚餐建议",
            text: "定时定量，细嚼慢咽；口味清淡、少油少盐，不喝含糖饮料。",
            tags: ["定时定量", "清淡少油盐", "无糖饮品"],
            guidelines: [.regularMeals, .lessSugarOilSalt]
        )
    ]

    static let careTasks = [
        CareTask(title: "早餐后测一次血糖", detail: "餐后 2 小时补一条读数，和早餐记录对照", isDone: true),
        CareTask(title: "午餐后活动一会儿", detail: "快走、骑车都可以，循序渐进；运动前后留意血糖", isDone: false),
        CareTask(title: "晚上回看今天的记录", detail: "对照餐后血糖，看看哪一餐的影响最大", isDone: false)
    ]
}
