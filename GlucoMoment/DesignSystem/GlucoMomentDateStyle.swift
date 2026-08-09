//
//  GlucoMomentDateStyle.swift
//  GlucoMoment
//

import Foundation

enum GlucoMomentDateStyle {
    static let mainlandChinaLocale = Locale(identifier: "zh_CN")

    static let monthDayTime = Date.FormatStyle()
        .month(.abbreviated)
        .day()
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .locale(mainlandChinaLocale)

    static let fullDateTime = Date.FormatStyle()
        .year()
        .month(.abbreviated)
        .day()
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .locale(mainlandChinaLocale)

    static let time = Date.FormatStyle()
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .locale(mainlandChinaLocale)

    static let weekday = Date.FormatStyle()
        .weekday(.narrow)
        .locale(mainlandChinaLocale)

    static let day = Date.FormatStyle()
        .day()
        .locale(mainlandChinaLocale)

    static let relative = Date.RelativeFormatStyle(presentation: .named)
        .locale(mainlandChinaLocale)
}
