//
//  DemoDataProvider.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

enum DemoDataProvider {
    static let readings = [
        GlucoseReading(hour: "07:00", value: 96, state: .inRange),
        GlucoseReading(hour: "09:00", value: 128, state: .inRange),
        GlucoseReading(hour: "11:00", value: 118, state: .inRange),
        GlucoseReading(hour: "13:00", value: 152, state: .elevated),
        GlucoseReading(hour: "15:00", value: 134, state: .inRange),
        GlucoseReading(hour: "17:00", value: 104, state: .inRange),
        GlucoseReading(hour: "19:00", value: 141, state: .inRange),
        GlucoseReading(hour: "21:00", value: 112, state: .inRange)
    ]

    static let weeklyReadings = [
        GlucoseReading(hour: "周一", value: 124, state: .inRange),
        GlucoseReading(hour: "周二", value: 132, state: .inRange),
        GlucoseReading(hour: "周三", value: 146, state: .inRange),
        GlucoseReading(hour: "周四", value: 158, state: .elevated),
        GlucoseReading(hour: "周五", value: 128, state: .inRange),
        GlucoseReading(hour: "周六", value: 118, state: .inRange),
        GlucoseReading(hour: "周日", value: 110, state: .inRange)
    ]

    static let monthlyReadings = [
        GlucoseReading(hour: "1日", value: 138, state: .inRange),
        GlucoseReading(hour: "5日", value: 144, state: .inRange),
        GlucoseReading(hour: "10日", value: 151, state: .elevated),
        GlucoseReading(hour: "15日", value: 133, state: .inRange),
        GlucoseReading(hour: "20日", value: 122, state: .inRange),
        GlucoseReading(hour: "25日", value: 116, state: .inRange),
        GlucoseReading(hour: "30日", value: 109, state: .inRange)
    ]

    static let mealGuidances: [MealPeriod: MealGuidance] = [
        .breakfast: MealGuidance(
            period: .breakfast,
            title: "早餐建议",
            text: "优先选高纤维主食和足量蛋白质，避免空腹直接吃甜水果；如果晨起偏高，主食先控制在 30-40g 碳水。",
            tags: ["高纤维", "蛋白质", "少精制糖"],
            meals: [
                MealEntry(
                    title: "燕麦酸奶碗",
                    time: "08:10",
                    carbs: "38g 碳水",
                    score: 88,
                    tags: ["低GI", "高纤维", "早餐"],
                    note: "搭配坚果和无糖希腊酸奶，餐后峰值预计温和。"
                ),
                MealEntry(
                    title: "鸡蛋全麦吐司",
                    time: "07:45",
                    carbs: "32g 碳水",
                    score: 84,
                    tags: ["快手", "高蛋白"],
                    note: "全麦吐司控制在 1-2 片，先吃鸡蛋和蔬菜。"
                )
            ]
        ),
        .lunch: MealGuidance(
            period: .lunch,
            title: "午餐建议",
            text: "午餐容易出现全天最高峰值，建议按“半盘蔬菜、四分之一蛋白、四分之一主食”搭配，并安排餐后短步行。",
            tags: ["餐盘法", "餐后步行", "控油"],
            meals: [
                MealEntry(
                    title: "鸡胸藜麦沙拉",
                    time: "12:35",
                    carbs: "45g 碳水",
                    score: 82,
                    tags: ["蛋白质", "控油", "午餐"],
                    note: "藜麦份量适中，建议餐后 15 分钟散步。"
                ),
                MealEntry(
                    title: "糙米牛肉蔬菜碗",
                    time: "12:20",
                    carbs: "49g 碳水",
                    score: 79,
                    tags: ["均衡", "可外卖"],
                    note: "糙米半份更稳，酱汁分开放能减少隐形糖。"
                )
            ]
        ),
        .dinner: MealGuidance(
            period: .dinner,
            title: "晚餐建议",
            text: "晚餐目标是稳住夜间血糖，主食不宜过晚过量；若白天活动少，可把一半主食换成豆制品或蔬菜。",
            tags: ["夜间稳定", "轻负担", "少油盐"],
            meals: [
                MealEntry(
                    title: "番茄牛肉荞麦面",
                    time: "18:40",
                    carbs: "52g 碳水",
                    score: 76,
                    tags: ["晚餐", "可替换"],
                    note: "面量略高，可下次把一半主食换成蔬菜。"
                ),
                MealEntry(
                    title: "豆腐虾仁杂蔬锅",
                    time: "18:15",
                    carbs: "28g 碳水",
                    score: 90,
                    tags: ["低碳水", "高蛋白"],
                    note: "适合晚间偏高时选择，可少量搭配杂粮饭。"
                )
            ]
        )
    ]

    static let careTasks = [
        CareTask(title: "早餐后记录血糖", detail: "餐后 2 小时补一条读数", isDone: true),
        CareTask(title: "午餐后轻运动", detail: "10-15 分钟低强度步行", isDone: false),
        CareTask(title: "晚餐主食复盘", detail: "对比今日峰值，调整明日份量", isDone: false)
    ]

    static let timelineEvents = [
        TimelineEvent(time: "08:10", title: "早餐记录", detail: "燕麦酸奶碗，餐后反应平稳", state: .inRange),
        TimelineEvent(time: "12:35", title: "午餐记录", detail: "碳水稍高，建议短步行", state: .low),
        TimelineEvent(time: "20:40", title: "待完成", detail: "晚餐后 2 小时血糖复测", state: .inRange)
    ]

    static let insights = [
        Insight(icon: "fork.knife", title: "午餐是今日最大波动来源", detail: "主食份量和餐后运动是下一次优化重点。"),
        Insight(icon: "bed.double", title: "夜间数据稳定", detail: "睡前无需加餐，保持补水即可。"),
        Insight(icon: "figure.walk", title: "活动有效压低峰值", detail: "餐后 10 分钟步行后，回落速度更稳定。")
    ]

    static let weeklyInsights = [
        Insight(icon: "calendar", title: "周四波动最明显", detail: "连续会议导致午餐偏晚，餐后活动不足。"),
        Insight(icon: "leaf", title: "周末早餐更稳定", detail: "高纤维早餐让上午曲线更平缓。"),
        Insight(icon: "figure.cooldown", title: "短步行有持续收益", detail: "餐后活动日的回落速度平均更快。")
    ]

    static let monthlyInsights = [
        Insight(icon: "chart.line.uptrend.xyaxis", title: "月中出现一次高峰", detail: "10 日附近外食增多，可重点复盘调味和主食份量。"),
        Insight(icon: "target", title: "后半月趋于稳定", detail: "晚餐结构调整后，夜间读数波动减少。"),
        Insight(icon: "checkmark.seal", title: "记录习惯正在形成", detail: "近 30 天餐食记录完整度高，趋势判断更可靠。")
    ]
}
