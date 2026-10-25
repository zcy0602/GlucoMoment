//
//  FoodAnalysisProxyEndpoint.swift
//  GlucoMoment
//

import Foundation

nonisolated enum FoodAnalysisProxyEndpoint {
    static let analysisPath = "/v1/food/analyze"
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
