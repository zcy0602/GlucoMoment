//
//  GlucoMomentTheme.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

extension Color {
    static let brandTeal = Color(red: 0.05, green: 0.55, blue: 0.50)
    static let brandMint = Color(red: 0.83, green: 0.95, blue: 0.91)
    static let brandLeaf = Color(red: 0.36, green: 0.63, blue: 0.35)
    static let brandAmber = Color(red: 0.94, green: 0.63, blue: 0.23)
    static let brandRose = Color(red: 0.88, green: 0.29, blue: 0.36)
}

extension GlucoseState {
    /// 偏低用红色、偏高用橙色：低血糖更危险，用更醒目的颜色（与鱼跃 Anytime 一致）
    var tint: Color {
        switch self {
        case .low:
            Color.brandRose
        case .inRange:
            Color.brandLeaf
        case .elevated:
            Color.brandAmber
        }
    }
}
