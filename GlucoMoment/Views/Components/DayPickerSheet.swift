//
//  DayPickerSheet.swift
//  GlucoMoment
//

import SwiftUI

/// 日历选择某一天，只能在 `range` 内选；选中后立即关闭。饮食页和血糖页共用
struct DayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    let title: String
    let range: ClosedRange<Date>
    let onSelect: (Date) -> Void

    init(
        title: String = "选择日期",
        selectedDate: Date,
        range: ClosedRange<Date>,
        onSelect: @escaping (Date) -> Void
    ) {
        _date = State(initialValue: selectedDate)
        self.title = title
        self.range = range
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            DatePicker("日期", selection: $date, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Color.brandTeal)
                .padding(.horizontal)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("今天") {
                            onSelect(range.upperBound)
                            dismiss()
                        }
                    }
                }
                .onChange(of: date) {
                    onSelect(date)
                    dismiss()
                }
        }
        .presentationDetents([.medium, .large])
    }
}
