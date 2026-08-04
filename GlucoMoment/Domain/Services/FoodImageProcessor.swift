//
//  FoodImageProcessor.swift
//  GlucoMoment
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FoodImageProcessor {
    static func prepareForAnalysis(_ data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw FoodAnalysisError.invalidImage
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                throw FoodAnalysisError.invalidImage
            }

            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw FoodAnalysisError.invalidImage
            }

            let properties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.76
            ]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw FoodAnalysisError.invalidImage
            }

            return output as Data
        }.value
    }
}
