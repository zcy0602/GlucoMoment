//
//  GlucoseEntryViewModel.swift
//  GlucoMoment
//

import Foundation
import Observation

@MainActor
@Observable
final class GlucoseEntryViewModel {
    let isEditing: Bool

    var value: Double?
    var measuredAt: Date
    var note: String
    private(set) var errorMessage: String?
    var isShowingError = false

    private let id: UUID
    private let source: GlucoseSource
    private let externalIdentifier: String?
    private let repository: any GlucoseRepository

    init(repository: any GlucoseRepository, reading: GlucoseReading?) {
        self.repository = repository
        self.id = reading?.id ?? UUID()
        self.value = reading?.value
        self.measuredAt = reading?.measuredAt ?? .now
        self.note = reading?.note ?? ""
        self.source = reading?.source ?? .manual
        self.externalIdentifier = reading?.externalIdentifier
        self.isEditing = reading != nil
    }

    var canSave: Bool {
        guard let value else { return false }
        return 0.1...50.0 ~= value
    }

    var validationMessage: String? {
        guard let value else { return "请输入血糖值" }
        guard 0.1...50.0 ~= value else { return "请输入 0.1–50.0 mmol/L 之间的数值" }
        return nil
    }

    func save() async -> Bool {
        guard canSave, let value else {
            errorMessage = validationMessage
            isShowingError = true
            return false
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = GlucoseReading(
            id: id,
            measuredAt: measuredAt,
            value: value,
            source: source,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            externalIdentifier: externalIdentifier
        )

        do {
            try await repository.save(reading)
            errorMessage = nil
            isShowingError = false
            return true
        } catch {
            errorMessage = "保存血糖记录失败：\(error.localizedDescription)"
            isShowingError = true
            return false
        }
    }
}
