//
//  MealPhotoPager.swift
//  GlucoMoment
//

import SwiftUI

/// 同一餐的多张照片左右滑动查看，右上角显示页码；只有一张时直接显示
struct MealPhotoPager<Photo: View>: View {
    let photos: [Data]
    /// 由外部持有当前页时传入（例如点开全屏查看要知道是第几张）；为 nil 时自己记
    var selection: Binding<Int>?
    @ViewBuilder let photo: (Data) -> Photo

    @State private var ownPage = 0

    init(photos: [Data], selection: Binding<Int>? = nil, @ViewBuilder photo: @escaping (Data) -> Photo) {
        self.photos = photos
        self.selection = selection
        self.photo = photo
    }

    private var pageBinding: Binding<Int> {
        selection ?? $ownPage
    }

    private var page: Int {
        pageBinding.wrappedValue
    }

    var body: some View {
        if photos.count > 1 {
            TabView(selection: pageBinding) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                    photo(data)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .topTrailing) {
                Text("\(min(page, photos.count - 1) + 1)/\(photos.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(24)
                    .accessibilityLabel("第 \(min(page, photos.count - 1) + 1) 张，共 \(photos.count) 张")
            }
            .onChange(of: photos.count) { _, count in
                pageBinding.wrappedValue = min(page, max(count - 1, 0))
            }
        } else if let first = photos.first {
            photo(first)
        }
    }
}
