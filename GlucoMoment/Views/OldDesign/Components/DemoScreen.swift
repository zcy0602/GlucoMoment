//
//  DemoScreen.swift
//  GlucoMoment
//
//  Created by zcy0602 on 2026/6/27.
//

import SwiftUI

struct DemoScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    private let contentPadding: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(
                    width: max(geometry.size.width - contentPadding * 2, 0),
                    alignment: .leading
                )
                .padding(contentPadding)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(title)
    }
}
