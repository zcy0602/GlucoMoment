//
//  FoodAnalysisProxyEndpoint.swift
//  GlucoMoment
//

import Foundation

nonisolated enum FoodAnalysisProxyEndpoint {
    static let analysisPath = "/v1/food/analyze"
    static let detectionPath = "/v1/food/detect"
    static let measuredEstimatePath = "/v1/food/estimate"
    static let healthPath = "/health"

    static func analysisURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let normalizedPath = components.path.isEmpty ? "/" : components.path
        switch normalizedPath {
        case "/":
            components.path = analysisPath
        case "\(analysisPath)/":
            components.path = analysisPath
        default:
            break
        }

        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// LiDAR 两段式识别的检测接口；与分析接口位于同一路径前缀下。
    static func detectionURL(from analysisURL: URL) -> URL? {
        siblingURL(of: analysisURL, path: detectionPath)
    }

    /// LiDAR 两段式识别的估算接口。
    static func measuredEstimateURL(from analysisURL: URL) -> URL? {
        siblingURL(of: analysisURL, path: measuredEstimatePath)
    }

    static func healthURL(from analysisURL: URL) -> URL? {
        guard var components = URLComponents(
            url: analysisURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        components.path = healthPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// 若分析地址形如 `https://host/prefix/v1/food/analyze`，则保留 `/prefix`；否则直接使用根路径。
    private static func siblingURL(of analysisURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: analysisURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let prefix = components.path.hasSuffix(analysisPath)
            ? String(components.path.dropLast(analysisPath.count))
            : ""
        components.path = prefix + path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
