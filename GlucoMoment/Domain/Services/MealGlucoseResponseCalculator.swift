//
//  MealGlucoseResponseCalculator.swift
//  GlucoMoment
//

import Foundation

/// 计算餐后反应用的一条血糖读数（mmol/L）
nonisolated struct GlucosePoint: Hashable, Sendable {
    var time: Date
    var value: Double
}

/// 一餐的餐后血糖反应
nonisolated struct MealGlucoseResponse: Hashable, Sendable {
    /// 记录的进餐时间
    var recordedStart: Date
    /// 计算用的开始时间：记录时间偏晚时为检测到的实际开始时间，否则等于记录时间
    var start: Date
    /// 开始前 15 分钟内读数的均值
    var baseline: Double
    var peak: Double
    var peakRise: Double
    var peakMinutes: Double
    /// 开始后 120 分钟时的值减去基线；该时刻没有数据时为 nil
    var rise2h: Double?
    /// 高于基线部分的增量曲线下面积（mmol/L·min），低于基线的部分记为 0
    var iAUC: Double
    /// 相对 `start` 的曲线，各点的分钟数见 `MealGlucoseResponseCalculator.curveOffsets`；超出数据范围为 nil
    var curve: [Double?]
    /// 开始前 45 分钟到开始后 180 分钟内有低于 3.9 的读数
    var hasLowReading: Bool

    /// 检测到的开始时间比记录时间早多少分钟；按记录时间计算时为 0
    var startShiftMinutes: Int {
        Int((recordedStart.timeIntervalSince(start) / 60).rounded())
    }
}

/// 餐后血糖反应，移植自 `验证分析/meal_response.py` 的 analyze、value_at 和 detect_onset。
/// 改算法或参数时两边同步，并用 `验证分析/response_fixture.py` 重新生成 `MealGlucoseResponseCalculatorTests` 的期望值。
nonisolated enum MealGlucoseResponseCalculator {
    static let windowMinutes = 120.0
    static let baselineMinutes = 15.0
    /// 窗口内至少要有的读数条数；只有指尖血的餐达不到，不计算
    static let minimumWindowReadings = 10
    static let maximumEndGapMinutes = 10.0

    // 起点检测，参数为团队设定，说明见 meal_response.py 的 detect_onset
    static let onsetLookbackMinutes = 60.0
    /// 记录时间前 15 分钟内升了这么多，视为记录时血糖已经在上升
    static let onsetRisingThreshold = 0.6
    /// 检测到的起点比记录早不到这么多分钟时不调整
    static let onsetMinimumShiftMinutes = 10.0
    static let onsetTolerance = 0.1

    /// 发给模型的曲线：开始前 45 分钟到开始后 180 分钟，每 15 分钟一个点
    static let curveOffsets = Array(stride(from: -45, through: 180, by: 15))
    /// 与 `GlucoseTargetRange.standard` 的下限一致
    static let lowThreshold = 3.9

    /// 窗口内数据不足（只有指尖血、传感器断档或不在数据范围内）时返回 nil
    static func response(recordedStart: Date, points: [GlucosePoint]) -> MealGlucoseResponse? {
        let points = points.sorted { $0.time < $1.time }
        let start = onset(recordedStart: recordedStart, sortedPoints: points)
        let end = start.addingTimeInterval(windowMinutes * 60)

        let pre = points.filter { $0.time >= start.addingTimeInterval(-baselineMinutes * 60) && $0.time <= start }
        let window = points.filter { $0.time >= start && $0.time <= end }
        guard window.count >= minimumWindowReadings,
              let last = window.last,
              minutes(from: last.time, to: end) <= maximumEndGapMinutes else {
            return nil
        }
        let baselineValue = pre.isEmpty
            ? value(at: start, sortedPoints: points)
            : pre.map(\.value).reduce(0, +) / Double(pre.count)
        guard let baseline = baselineValue, let peakPoint = window.max(by: { $0.value < $1.value }) else {
            return nil
        }

        var iAUC = 0.0
        for (first, second) in zip(window, window.dropFirst()) {
            let d0 = first.value - baseline
            let d1 = second.value - baseline
            let span = minutes(from: first.time, to: second.time)
            if d0 >= 0 && d1 >= 0 {
                iAUC += (d0 + d1) / 2 * span
            } else if d0 > 0 || d1 > 0 {
                // 穿越基线：只取高于基线的三角形部分
                let positive = max(d0, d1)
                iAUC += positive * span * positive / (abs(d0) + abs(d1)) / 2
            }
        }

        let lowCheckStart = start.addingTimeInterval(Double(curveOffsets.first ?? 0) * 60)
        let lowCheckEnd = start.addingTimeInterval(Double(curveOffsets.last ?? 0) * 60)
        return MealGlucoseResponse(
            recordedStart: recordedStart,
            start: start,
            baseline: baseline,
            peak: peakPoint.value,
            peakRise: peakPoint.value - baseline,
            peakMinutes: minutes(from: start, to: peakPoint.time),
            rise2h: value(at: end, sortedPoints: points).map { $0 - baseline },
            iAUC: iAUC,
            curve: curveOffsets.map { value(at: start.addingTimeInterval(Double($0) * 60), sortedPoints: points) },
            hasLowReading: points.contains {
                $0.time >= lowCheckStart && $0.time <= lowCheckEnd && $0.value < lowThreshold
            }
        )
    }

    /// 记录时间偏晚时，把血糖开始上升前的最低点当作实际开始时间；只会往前调，不会往后调
    static func onset(recordedStart: Date, sortedPoints points: [GlucosePoint]) -> Date {
        guard let now = value(at: recordedStart, sortedPoints: points),
              let before = value(at: recordedStart.addingTimeInterval(-baselineMinutes * 60), sortedPoints: points),
              now - before >= onsetRisingThreshold else {
            return recordedStart
        }
        let lookback = points.filter {
            $0.time >= recordedStart.addingTimeInterval(-onsetLookbackMinutes * 60) && $0.time <= recordedStart
        }
        guard let lowest = lookback.map(\.value).min(),
              let candidate = lookback.last(where: { $0.value <= lowest + onsetTolerance })?.time else {
            return recordedStart
        }
        return minutes(from: candidate, to: recordedStart) >= onsetMinimumShiftMinutes ? candidate : recordedStart
    }

    /// 相邻两条读数之间线性插值；超出数据范围时为 nil
    static func value(at time: Date, sortedPoints points: [GlucosePoint]) -> Double? {
        for (first, second) in zip(points, points.dropFirst()) where first.time <= time && time <= second.time {
            let span = minutes(from: first.time, to: second.time)
            return span == 0
                ? first.value
                : first.value + (second.value - first.value) * minutes(from: first.time, to: time) / span
        }
        return nil
    }

    private static func minutes(from start: Date, to end: Date) -> Double {
        end.timeIntervalSince(start) / 60
    }
}
