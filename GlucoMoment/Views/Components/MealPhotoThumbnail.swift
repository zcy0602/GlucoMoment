//
//  MealPhotoThumbnail.swift
//  GlucoMoment
//

import SwiftUI
import UIKit

/// 餐食照片缩略图：读取第一张照片并缩小后显示；没有照片时显示餐具图标
struct MealPhotoThumbnail: View {
    let filename: String?
    let photoStore: any MealPhotoStoring
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.mealTint.opacity(0.12)
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(Color.mealTint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: filename) {
            guard let filename,
                  let data = await photoStore.jpegData(filename: filename),
                  let full = UIImage(data: data) else {
                image = nil
                return
            }
            // 缩略图只需要显示尺寸的 3 倍，避免在列表里解码整张照片
            let target = CGSize(width: size * 3, height: size * 3)
            image = await full.byPreparingThumbnail(ofSize: target) ?? full
        }
        .accessibilityHidden(true)
    }
}

/// 识别流程里还没保存的照片，直接用内存中的数据显示
struct PhotoDataImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
