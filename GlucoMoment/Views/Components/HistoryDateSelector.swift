//
//  HistoryDateSelector.swift
//  GlucoMoment
//

import SwiftUI

struct HistoryDateSelector: View {
    @Binding var selectedDate: Date

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            Button("前一天", systemImage: "chevron.left", action: selectPreviousDay)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)

            Spacer(minLength: 8)

            DatePicker(
                "查询日期",
                selection: $selectedDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.locale, GlucoMomentDateStyle.mainlandChinaLocale)
            .datePickerStyle(.compact)
            .accessibilityLabel("查询日期")

            Spacer(minLength: 8)

            Button("后一天", systemImage: "chevron.right", action: selectNextDay)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(calendar.isDateInToday(selectedDate))
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
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
