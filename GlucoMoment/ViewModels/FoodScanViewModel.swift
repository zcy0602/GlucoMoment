//
//  FoodScanViewModel.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/7/6.
//

import Observation

@Observable
final class FoodScanViewModel {
    let title = "拍照识别"
    let result = FoodRecognitionResult(
        name: "鸡胸藜麦沙拉",
        confidence: "92%",
        calories: "450 千卡",
        carbs: "45g",
        protein: "32g",
        fat: "18g",
        glucoseImpact: "中等",
        score: 82,
        ingredients: ["鸡胸肉", "藜麦", "生菜", "番茄", "牛油果"],
        suggestions: [
            "藜麦份量适中，建议餐后 15 分钟轻步行。",
            "如果今日午餐后血糖偏高，下次可把藜麦减到半份。",
            "蛋白质充足，可以先吃鸡胸肉和蔬菜再吃主食。"
        ]
    )

    var scanStateText: String {
        "已识别 · 置信度 \(result.confidence)"
    }

    var saveButtonTitle: String {
        "保存到饮食记录"
    }
}
