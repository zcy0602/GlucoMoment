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

    /// 纯数字的「11/1 01:55」，用在血糖页最新读数下方。计算属性，跟随当前时区
    static var numericMonthDayTime: Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: "\(month: .defaultDigits)/\(day: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: mainlandChinaLocale,
            timeZone: .current,
            calendar: .current
        )
    }

    /// 纯数字的「11/1」，用在复盘覆盖的日期范围。计算属性，跟随当前时区
    static var numericMonthDay: Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: "\(month: .defaultDigits)/\(day: .defaultDigits)",
            locale: mainlandChinaLocale,
            timeZone: .current,
            calendar: .current
        )
    }

    static let weekday = Date.FormatStyle()
        .weekday(.narrow)
        .locale(mainlandChinaLocale)

    static let day = Date.FormatStyle()
        .day()
        .locale(mainlandChinaLocale)

    static let relative = Date.RelativeFormatStyle(presentation: .named)
        .locale(mainlandChinaLocale)
}
