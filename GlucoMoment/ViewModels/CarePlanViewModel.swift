//
//  CarePlanViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import Observation

@Observable
final class CarePlanViewModel {
    let title = "个人方案"
    /// 只写行为目标，不写血糖指标数值；个人的控制目标由医生确定
    let weeklyGoal = "每天记录三餐，并在餐后测一次血糖，积累自己的饮食与血糖对照。"
    let progress = 0.72
    let notes = [
        "主食定量，全谷物和杂豆占主食的 1/3 以上。",
        "每周至少 5 天餐后活动，运动前后留意血糖。",
        "任何用药调整都应咨询医生，本 App 只做记录和提醒。"
    ]
    let notesCitation = DietGuideline.citation(for: [.wholeGrainShare, .activityAfterMeals])

    var reminderEnabled = true
    var tasks: [CareTask]

    init(tasks: [CareTask] = DemoDataProvider.careTasks) {
        self.tasks = tasks
    }

    var progressText: String {
        "当前进度 \(Int(progress * 100))%"
    }

    func toggleTask(_ task: CareTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
    }
}
