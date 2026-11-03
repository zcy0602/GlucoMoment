//
//  MealPhotoViewer.swift
//  GlucoMoment
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 全屏查看一餐的照片：黑底、左右滑动切换、双指或双击缩放，右上角菜单可以保存、分享、拷贝
struct MealPhotoViewer: View {
    let photos: [Data]
    @Binding var page: Int

    @Environment(\.dismiss) private var dismiss
    @State private var saving = PhotoSaveFeedback()

    private var currentPhoto: Data? {
        photos.indices.contains(page) ? photos[page] : photos.first
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                ZoomablePhoto(data: data)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar }
        .photoSaveFeedback(saving)
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack {
            Button("关闭", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            if photos.count > 1 {
                Text("\(min(page, photos.count - 1) + 1)/\(photos.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityLabel("第 \(min(page, photos.count - 1) + 1) 张，共 \(photos.count) 张")
            }

            Spacer()

            if let currentPhoto {
                Menu {
                    MealPhotoActionButtons(data: currentPhoto) { saving.save(currentPhoto) }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
    }
}

/// 照片的三个操作，长按菜单和全屏查看器的菜单共用
struct MealPhotoActionButtons: View {
    let data: Data
    let onSave: () -> Void

    var body: some View {
        Button("保存到相册", systemImage: "square.and.arrow.down", action: onSave)
        if let image = UIImage(data: data) {
            ShareLink(
                item: SharedMealPhoto(data: data),
                preview: SharePreview("餐食照片", image: Image(uiImage: image))
            ) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            Button("拷贝", systemImage: "doc.on.doc") {
                UIPasteboard.general.image = image
            }
        }
    }
}

/// 分享时按原样导出 JPEG，不经过 `Image` 重新编码成 PNG
private struct SharedMealPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.data }
            .suggestedFileName("餐食照片.jpg")
    }
}

/// 保存照片到相册，并给出反馈：成功时轻震并短暂显示「已保存到相册」，失败时弹窗说明原因
@MainActor
@Observable
final class PhotoSaveFeedback {
    private(set) var savedCount = 0
    var isShowingSaved = false
    var errorMessage: String?

    private let library: any PhotoLibrarySaving
    private var hideTask: Task<Void, Never>?

    init(library: any PhotoLibrarySaving = SystemPhotoLibrary()) {
        self.library = library
    }

    func save(_ data: Data) {
        Task {
            do {
                try await library.save([data], creationDate: nil)
                savedCount += 1
                showSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func showSaved() {
        hideTask?.cancel()
        withAnimation(.snappy) { isShowingSaved = true }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { isShowingSaved = false }
        }
    }
}

extension View {
    /// 显示 `PhotoSaveFeedback` 的保存结果
    func photoSaveFeedback(_ feedback: PhotoSaveFeedback) -> some View {
        modifier(PhotoSaveFeedbackModifier(feedback: feedback))
    }
}

private struct PhotoSaveFeedbackModifier: ViewModifier {
    @Bindable var feedback: PhotoSaveFeedback

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if feedback.isShowingSaved {
                    Label("已保存到相册", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sensoryFeedback(.success, trigger: feedback.savedCount)
            .alert("没有保存", isPresented: isShowingError) {
            } message: {
                Text(feedback.errorMessage ?? "")
            }
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            feedback.errorMessage != nil
        } set: { isShowing in
            if !isShowing { feedback.errorMessage = nil }
        }
    }
}

/// 可缩放的单张照片。缩放交给 `UIScrollView`，手感和系统相册一致：双指缩放，双击放大或还原
private struct ZoomablePhoto: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scrollView = ZoomingScrollView()
        scrollView.imageView.image = UIImage(data: data)
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {}
}

private final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 未缩放时让图片铺满可视区域；缩放中由 UIScrollView 管理图片的尺寸
        if zoomScale == minimumZoomScale, imageView.frame.size != bounds.size {
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            let rect = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            zoom(to: rect, animated: true)
        }
    }
}
