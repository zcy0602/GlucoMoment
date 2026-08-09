//
//  HistoryDateSelector.swift
//  GlucoMoment
//

import SwiftUI

struct HistoryDateSelector: View {
    @Binding var selectedDate: Date

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 8) {
            Button("前一天", systemImage: "chevron.left", action: selectPreviousDay)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)

            DatePicker(
                "查询日期",
                selection: $selectedDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)

            Button("后一天", systemImage: "chevron.right", action: selectNextDay)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(calendar.isDateInToday(selectedDate))
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func selectPreviousDay() {
        selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
    }

    private func selectNextDay() {
        guard !calendar.isDateInToday(selectedDate) else { return }
        let nextDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        selectedDate = min(nextDate, .now)
    }
}

#Preview {
    @Previewable @State var selectedDate = Calendar.current.date(
        byAdding: .day,
        value: -1,
        to: .now
    ) ?? .now

    HistoryDateSelector(selectedDate: $selectedDate)
        .padding()
}
