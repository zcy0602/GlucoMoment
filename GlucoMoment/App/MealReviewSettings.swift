//
//  MealReviewSettings.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 近期复盘的开关，默认关闭。开启前必须看过 `MealReviewConsentView` 的数据发送说明并同意
/// （Apple 审核指南 5.1.2(i)、5.1.3；健康信息属于敏感个人信息，需要单独同意）
@MainActor
@Observable
final class MealReviewSettings {
    private enum Key {
        static let enabled = "GlucoMoment.MealReview.Enabled"
    }

    var isEnabled: Bool {
        didSet { defaults?.set(isEnabled, forKey: Key.enabled) }
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
    }

    init(isEnabled: Bool) {
        defaults = nil
        self.isEnabled = isEnabled
    }
}

extension FoodAnalysisSettings {
    /// 近期复盘的数据发往哪里，与当前的识别方式一致，用于授权说明
    var reviewDestinationDescription: String {
        switch mode {
        case .demo:
            "当前是演示模式：复盘在本机按固定模板生成，不发送任何数据。"
        case .directAPI:
            "当前识别方式是自定义 API：数据会用你填写的 Key 发送给\(apiProvider.title)。"
        case .proxy:
            "当前识别方式是自建代理：数据会发送到稳糖食刻的代理服务器（\(Self.proxyServerAddress)），由它转给模型，代理不保存数据。"
        }
    }
}
