//
//  GlucoMomentDateStyleTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@Suite("中国大陆日期格式")
struct GlucoMomentDateStyleTests {
    @Test("月日和时间使用中文 24 小时制")
    func formatsMonthDayTime() {
        let date = sampleDate()
        var format = GlucoMomentDateStyle.monthDayTime
        format.timeZone = shanghaiTimeZone

        #expect(date.formatted(format) == "8月9日 20:31")
    }

    @Test("完整日期包含中文年月日")
    func formatsFullDateTime() {
        let date = sampleDate()
        var format = GlucoMomentDateStyle.fullDateTime
        format.timeZone = shanghaiTimeZone

        #expect(date.formatted(format) == "2026年8月9日 20:31")
    }

    @Test("纯时间、星期和日号使用中文样式")
    func formatsCompactDateParts() {
        let date = sampleDate()
        var timeFormat = GlucoMomentDateStyle.time
        var weekdayFormat = GlucoMomentDateStyle.weekday
        var dayFormat = GlucoMomentDateStyle.day
        timeFormat.timeZone = shanghaiTimeZone
        weekdayFormat.timeZone = shanghaiTimeZone
        dayFormat.timeZone = shanghaiTimeZone

        #expect(date.formatted(timeFormat) == "20:31")
        #expect(date.formatted(weekdayFormat) == "日")
        #expect(date.formatted(dayFormat) == "9日")
    }

    private var shanghaiTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Shanghai")!
    }

    private func sampleDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghaiTimeZone
        return calendar.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 9,
                hour: 20,
                minute: 31
            )
        )!
    }
}
