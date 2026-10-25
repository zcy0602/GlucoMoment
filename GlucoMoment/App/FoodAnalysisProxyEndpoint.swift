//
//  FoodAnalysisProxyEndpoint.swift
//  GlucoMoment
//

import Foundation

nonisolated enum FoodAnalysisProxyEndpoint {
    static let analysisPath = "/v1/food/analyze"
    static let correctionPath = "/v1/food/correct"
    static let healthPath = "/health"

    static func analysisURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
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

    /// 修正接口与识别接口在同一个代理上：识别地址以 analyze 结尾时换成 correct，否则使用默认路径
    static func correctionURL(from analysisURL: URL) -> URL? {
        guard var components = URLComponents(
            url: analysisURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        if components.path.hasSuffix("/analyze") {
            components.path = String(components.path.dropLast("analyze".count)) + "correct"
        } else {
            components.path = correctionPath
        }
        components.query = nil
        components.fragment = nil
        return components.url
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
}
