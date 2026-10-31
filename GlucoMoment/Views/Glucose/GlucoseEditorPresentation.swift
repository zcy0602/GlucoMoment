//
//  GlucoseEditorPresentation.swift
//  GlucoMoment
//

import Foundation

struct GlucoseEditorPresentation: Identifiable {
    let id = UUID()
    let reading: GlucoseReading?

    static var newReading: GlucoseEditorPresentation {
        GlucoseEditorPresentation(reading: nil)
    }
}
