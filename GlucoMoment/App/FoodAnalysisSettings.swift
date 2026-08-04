//
//  FoodAnalysisSettings.swift
//  GlucoMoment
//

import Foundation
import Observation

nonisolated enum FoodAnalysisConnectionMode: String, CaseIterable, Identifiable, Sendable {
    case demo
    case directQwen
    case proxy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: "演示模式"
        case .directQwen: "App 内直连"
        case .proxy: "自建代理"
        }
    }

    var detail: String {
        switch self {
        case .demo: "不联网，不产生模型费用"
        case .directQwen: "使用保存在本机钥匙串中的阿里云 API Key"
        case .proxy: "图片与描述发送到你部署的代理服务"
        }
    }
}

nonisolated struct FoodAnalysisRuntimeConfiguration: Sendable {
    let mode: FoodAnalysisConnectionMode
    let proxyEndpoint: URL?
}

@MainActor
@Observable
final class FoodAnalysisSettings {
    private enum Key {
        static let mode = "GlucoMoment.FoodAnalysis.Mode"
        static let proxyEndpoint = "GlucoMoment.FoodAnalysis.ProxyEndpoint"
    }

    nonisolated static let qwenModel = "qwen3.7-plus"
    nonisolated static let qwenEndpoint = URL(
        string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    )!

    var mode: FoodAnalysisConnectionMode {
        didSet { persistMode() }
    }

    var proxyEndpointString: String {
        didSet { persistProxyEndpoint() }
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = FoodAnalysisConnectionMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .demo
        proxyEndpointString = defaults.string(forKey: Key.proxyEndpoint) ?? ""
    }

    init(mode: FoodAnalysisConnectionMode, proxyEndpointString: String = "") {
        defaults = nil
        self.mode = mode
        self.proxyEndpointString = proxyEndpointString
    }

    var runtimeConfiguration: FoodAnalysisRuntimeConfiguration {
        FoodAnalysisRuntimeConfiguration(
            mode: mode,
            proxyEndpoint: validatedProxyEndpoint
        )
    }

    var validatedProxyEndpoint: URL? {
        let trimmed = proxyEndpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func persistMode() {
        defaults?.set(mode.rawValue, forKey: Key.mode)
    }

    private func persistProxyEndpoint() {
        defaults?.set(proxyEndpointString, forKey: Key.proxyEndpoint)
    }
}
