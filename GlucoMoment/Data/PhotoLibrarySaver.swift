//
//  PhotoLibrarySaver.swift
//  GlucoMoment
//

import Foundation
import Photos

/// 把照片存进系统相册。只申请「仅添加」权限，读不到用户相册里的照片
nonisolated protocol PhotoLibrarySaving: Sendable {
    /// 按顺序存入相册；`creationDate` 为 nil 时由系统记为保存时间
    func save(_ photos: [Data], creationDate: Date?) async throws
}

nonisolated enum PhotoLibrarySaveError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "没有添加照片的权限，可以在「设置」>「稳糖食刻」>「照片」里打开。"
        }
    }
}

nonisolated struct SystemPhotoLibrary: PhotoLibrarySaving {
    func save(_ photos: [Data], creationDate: Date?) async throws {
        guard !photos.isEmpty else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.notAuthorized
        }
        try await PHPhotoLibrary.shared().performChanges {
            for data in photos {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                if let creationDate {
                    request.creationDate = creationDate
                }
            }
        }
    }
}

/// 「拍照后保存到相册」开关，默认打开。只影响 App 内相机拍的照片，从相册选的照片本来就在相册里
nonisolated enum CameraPhotoSavingPreference {
    static let key = "GlucoMoment.Photos.SaveCameraPhotos"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
