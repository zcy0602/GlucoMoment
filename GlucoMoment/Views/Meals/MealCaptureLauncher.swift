//
//  MealCaptureLauncher.swift
//  GlucoMoment
//

import PhotosUI
import SwiftUI
import UIKit

/// 记录一餐的照片来源
enum MealPhotoSource: Hashable, Identifiable {
    case camera
    case library

    var id: Self { self }
}

extension View {
    /// 给任意页面加上「记录一餐」的入口：把 `source` 设为相机或相册，选好照片后弹出记录流程。
    /// 饮食页使用，保存后调用 `onSaved` 刷新列表
    func mealCapture(
        source: Binding<MealPhotoSource?>,
        dependencies: AppDependencies,
        onSaved: @escaping () -> Void
    ) -> some View {
        modifier(MealCaptureLauncher(source: source, dependencies: dependencies, onSaved: onSaved))
    }
}

/// 一组刚选好的照片，作为记录流程 sheet 的 item
private struct CapturedMealPhotos: Identifiable {
    let id = UUID()
    let photos: [Data]
}

private struct MealCaptureLauncher: ViewModifier {
    @Binding var source: MealPhotoSource?
    let dependencies: AppDependencies
    let onSaved: () -> Void

    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var captured: CapturedMealPhotos?
    @State private var issue: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: source) { _, newValue in
                guard let newValue else { return }
                source = nil
                switch newValue {
                case .camera:
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                    } else {
                        issue = "这台设备没有可用的相机，可以从相册选择照片。"
                    }
                case .library:
                    isShowingLibrary = true
                }
            }
            .photosPicker(
                isPresented: $isShowingLibrary,
                selection: $libraryItems,
                maxSelectionCount: FoodAnalysisImageLimit.maxImageCount,
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: libraryItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    do {
                        captured = CapturedMealPhotos(photos: try await PhotoLoading.load(items))
                    } catch {
                        issue = "照片读取失败，请换一张或重试。"
                    }
                    libraryItems = []
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView { data in
                    captured = CapturedMealPhotos(photos: [data])
                }
                .ignoresSafeArea()
            }
            .sheet(item: $captured) { captured in
                MealCaptureView(
                    photos: captured.photos,
                    dependencies: dependencies,
                    onSaved: onSaved
                )
            }
            .alert("无法使用照片", isPresented: isShowingIssue) {
            } message: {
                Text(issue ?? "")
            }
    }

    private var isShowingIssue: Binding<Bool> {
        Binding {
            issue != nil
        } set: { isShowing in
            if !isShowing { issue = nil }
        }
    }
}

/// 按选择顺序读取相册照片；任一张失败时整体放弃，避免一餐只录入部分照片
enum PhotoLoading {
    struct InvalidPhoto: Error {}

    static func load(_ items: [PhotosPickerItem]) async throws -> [Data] {
        var photos: [Data] = []
        for item in items {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                throw InvalidPhoto()
            }
            photos.append(data)
        }
        return photos
    }
}

/// 系统相机。拍完返回 JPEG 数据；取消时直接关闭
struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9)
            parent.dismiss()
            if let data {
                parent.onCapture(data)
            }
        }
    }
}
