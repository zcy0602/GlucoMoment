//
//  MealPhotoStore.swift
//  GlucoMoment
//

import Foundation

protocol MealPhotoStoring: Sendable {
    func saveJPEG(_ data: Data, mealID: UUID) async throws -> String
    func jpegData(filename: String) async -> Data?
    func delete(filename: String) async
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

    func saveJPEG(_ data: Data, mealID: UUID) async throws -> String {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let filename = "\(mealID.uuidString.lowercased()).jpg"
        try data.write(to: directoryURL.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func jpegData(filename: String) async -> Data? {
        try? Data(contentsOf: directoryURL.appendingPathComponent(filename))
    }

    func delete(filename: String) async {
        try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(filename))
    }
}

actor InMemoryMealPhotoStore: MealPhotoStoring {
    private var photos: [String: Data] = [:]

    func saveJPEG(_ data: Data, mealID: UUID) async throws -> String {
        let filename = "\(mealID.uuidString.lowercased()).jpg"
        photos[filename] = data
        return filename
    }

    func jpegData(filename: String) async -> Data? {
        photos[filename]
    }

    func delete(filename: String) async {
        photos[filename] = nil
    }
}
