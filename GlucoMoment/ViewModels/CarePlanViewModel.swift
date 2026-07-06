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
    let weeklyGoal = "把范围内时间提升到 88%，减少午餐后波动。"
    let progress = 0.72
    let notes = [
        "优先稳定早餐和午餐后的峰值。",
        "连续 3 天晚餐后低于 140 时，可保持当前晚餐结构。",
        "任何用药调整都应咨询医生，本 App 只做记录和提醒。"
    ]

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
