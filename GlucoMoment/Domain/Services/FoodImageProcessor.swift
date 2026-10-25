//
//  FoodImageProcessor.swift
//  GlucoMoment
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FoodImageProcessor {
    /// 读取 EXIF 中的拍摄时间；须在 `prepareForAnalysis` 去掉元数据之前调用。
    /// 只读取文件头，不解码图片。相机拍摄（`UIImage.jpegData`）和截图通常没有该字段，返回 nil。
    nonisolated static func captureDate(of data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else {
            return nil
        }

        let pairs: [(date: CFString, offset: CFString)] = [
            (kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifOffsetTimeOriginal),
            (kCGImagePropertyExifDateTimeDigitized, kCGImagePropertyExifOffsetTimeDigitized)
        ]
        for pair in pairs {
            guard let text = exif[pair.date] as? String else { continue }
            // 没有时区偏移时按手机当前时区理解，与系统相册的显示一致
            let timeZone = (exif[pair.offset] as? String).flatMap(timeZone(fromEXIFOffset:)) ?? .current
            if let date = try? Date(text, strategy: exifDateStrategy(timeZone: timeZone)) {
                return date
            }
        }
        return nil
    }

    /// EXIF 时间格式为 `yyyy:MM:dd HH:mm:ss`
    private nonisolated static func exifDateStrategy(timeZone: TimeZone) -> Date.ParseStrategy {
        Date.ParseStrategy(
            format: "\(year: .defaultDigits):\(month: .twoDigits):\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
    }

    /// 解析 `+08:00` / `-05:30` 形式的偏移
    private nonisolated static func timeZone(fromEXIFOffset offset: String) -> TimeZone? {
        let parts = offset.dropFirst().split(separator: ":")
        guard let sign = offset.first, sign == "+" || sign == "-",
              parts.count == 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else {
            return nil
        }
        let seconds = (hours * 3_600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }

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
