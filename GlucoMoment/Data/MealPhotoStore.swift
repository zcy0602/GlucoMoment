//
//  MealPhotoStore.swift
//  GlucoMoment
//

import Foundation

/// 一餐可以有多张照片：第一张保存为 `<mealID>.jpg`，即 `MealRecord.photoFilename`；
/// 其余依次保存为 `<mealID>-2.jpg`、`<mealID>-3.jpg`…，按主文件名即可找回，无需改动 Schema
protocol MealPhotoStoring: Sendable {
    /// 返回第一张照片的文件名
    func saveJPEGs(_ photos: [Data], mealID: UUID) async throws -> String
    func jpegData(filename: String) async -> Data?
    /// 按顺序返回主文件及其附加照片
    func allJPEGData(primaryFilename: String) async -> [Data]
    /// 同时删除附加照片
    func delete(filename: String) async
}

extension MealPhotoStoring {
    func saveJPEG(_ data: Data, mealID: UUID) async throws -> String {
        try await saveJPEGs([data], mealID: mealID)
    }
}

nonisolated enum MealPhotoFilename {
    static func primary(mealID: UUID) -> String {
        "\(mealID.uuidString.lowercased()).jpg"
    }

    /// `position` 从 2 开始
    static func additional(primaryFilename: String, position: Int) -> String {
        let stem = (primaryFilename as NSString).deletingPathExtension
        return "\(stem)-\(position).jpg"
    }

    static func all(primaryFilename: String, count: Int) -> [String] {
        [primaryFilename] + (1..<max(count, 1)).map {
            additional(primaryFilename: primaryFilename, position: $0 + 1)
        }
    }
}

actor LocalMealPhotoStore: MealPhotoStoring {
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = applicationSupport
            .appendingPathComponent("GlucoMoment", isDirectory: true)
            .appendingPathComponent("MealPhotos", isDirectory: true)
    }

    func saveJPEGs(_ photos: [Data], mealID: UUID) async throws -> String {
        guard !photos.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let primary = MealPhotoFilename.primary(mealID: mealID)
        let filenames = MealPhotoFilename.all(primaryFilename: primary, count: photos.count)
        do {
            for (data, filename) in zip(photos, filenames) {
                try data.write(to: directoryURL.appendingPathComponent(filename), options: .atomic)
            }
        } catch {
            await delete(filename: primary)
            throw error
        }
        return primary
    }

    func jpegData(filename: String) async -> Data? {
        try? Data(contentsOf: directoryURL.appendingPathComponent(filename))
    }

    func allJPEGData(primaryFilename: String) async -> [Data] {
        guard let first = await jpegData(filename: primaryFilename) else { return [] }
        var photos = [first]
        var position = 2
        while let next = await jpegData(
            filename: MealPhotoFilename.additional(primaryFilename: primaryFilename, position: position)
        ) {
            photos.append(next)
            position += 1
        }
        return photos
    }

    func delete(filename: String) async {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directoryURL.appendingPathComponent(filename))
        var position = 2
        while true {
            let url = directoryURL.appendingPathComponent(
                MealPhotoFilename.additional(primaryFilename: filename, position: position)
            )
            guard fileManager.fileExists(atPath: url.path) else { break }
            try? fileManager.removeItem(at: url)
            position += 1
        }
    }
}

actor InMemoryMealPhotoStore: MealPhotoStoring {
    private var photos: [String: Data] = [:]

    func saveJPEGs(_ photos: [Data], mealID: UUID) async throws -> String {
        guard !photos.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let primary = MealPhotoFilename.primary(mealID: mealID)
        let filenames = MealPhotoFilename.all(primaryFilename: primary, count: photos.count)
        for (data, filename) in zip(photos, filenames) {
            self.photos[filename] = data
        }
        return primary
    }

    func jpegData(filename: String) async -> Data? {
        photos[filename]
    }

    func allJPEGData(primaryFilename: String) async -> [Data] {
        guard let first = photos[primaryFilename] else { return [] }
        var result = [first]
        var position = 2
        while let next = photos[MealPhotoFilename.additional(primaryFilename: primaryFilename, position: position)] {
            result.append(next)
            position += 1
        }
        return result
    }

    func delete(filename: String) async {
        photos[filename] = nil
        var position = 2
        while photos.removeValue(
            forKey: MealPhotoFilename.additional(primaryFilename: filename, position: position)
        ) != nil {
            position += 1
        }
    }
}
