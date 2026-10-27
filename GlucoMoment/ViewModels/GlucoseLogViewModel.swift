//
//  GlucoseLogViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

/// 新版「所有血糖记录」：最近 30 天的读数按天分组，最新的在前
@MainActor
@Observable
final class GlucoseLogViewModel {
    static let dayCount = 30

    struct DayGroup: Identifiable {
        let day: Date
        let readings: [GlucoseReading]

        var id: Date { day }
    }

    private let repository: any GlucoseRepository
    private let calendar: Calendar

    private(set) var readings: [GlucoseReading] = []
    private(set) var errorMessage: String?

    init(repository: any GlucoseRepository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    var dayGroups: [DayGroup] {
        Dictionary(grouping: readings) { calendar.startOfDay(for: $0.measuredAt) }
            .map { DayGroup(day: $0.key, readings: $0.value.sorted { $0.measuredAt > $1.measuredAt }) }
            .sorted { $0.day > $1.day }
    }

    func load(now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(Self.dayCount - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else {
            readings = []
            return
        }

        do {
            readings = try repository.readings(in: DateInterval(start: start, end: end))
            errorMessage = nil
        } catch {
            readings = []
            errorMessage = "读取血糖记录失败：\(error.localizedDescription)"
        }
    }

    func delete(_ reading: GlucoseReading) async {
        do {
            try await repository.delete(id: reading.id)
            load()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}
