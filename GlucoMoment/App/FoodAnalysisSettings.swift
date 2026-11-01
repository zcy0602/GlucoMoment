//
//  FoodAnalysisSettings.swift
//  GlucoMoment
//

import Foundation
import Observation

nonisolated enum FoodAnalysisConnectionMode: String, CaseIterable, Identifiable, Sendable {
    case demo
    // 原始值沿用旧版的 directQwen，保证升级后用户已选的模式不丢失
    case directAPI = "directQwen"
    case proxy

    var id: String { rawValue }

    /// 设置页可选的识别方式。演示模式只在 Debug 包里提供，Release 包只能选自定义 API 或自建代理
    static var selectableCases: [FoodAnalysisConnectionMode] {
        #if DEBUG
        allCases
        #else
        [.directAPI, .proxy]
        #endif
    }

    var title: String {
        switch self {
        case .demo: "演示模式"
        case .directAPI: "自定义 API"
        case .proxy: "自建代理"
        }
    }

    var detail: String {
        switch self {
        case .demo: "不联网，不产生模型费用"
        case .directAPI: "使用你自己的 API Key 连接 OpenAI 兼容服务"
        case .proxy: "图片与描述发送到 App 预置的代理服务"
        }
    }
}

/// 用户自备 Key 时可选的服务商。均通过 OpenAI Chat Completions 兼容协议调用。
nonisolated enum FoodAnalysisAPIProvider: String, CaseIterable, Identifiable, Sendable {
    case dashScope
    case openAI
    case gemini
    case zhipu
    case volcengineArk
    case moonshot
    case deepSeek
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashScope: "阿里云百炼"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .zhipu: "智谱 BigModel"
        case .volcengineArk: "火山方舟"
        case .moonshot: "Kimi（月之暗面）"
        case .deepSeek: "DeepSeek"
        case .custom: "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .dashScope: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .volcengineArk: "https://ark.cn-beijing.volces.com/api/v3"
        case .moonshot: "https://api.moonshot.cn/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .custom: ""
        }
    }

    /// 预设的推荐模型，必须支持图片输入；用户可以手动修改或从模型列表选择
    var defaultModel: String {
        switch self {
        case .dashScope: "qwen3.7-plus"
        case .openAI: "gpt-6-luna"
        case .gemini: "gemini-3.8-flash"
        case .zhipu: "glm-4.6v"
        case .volcengineArk: "doubao-seed-2-1-pro-260628"
        case .moonshot: "kimi-k3"
        // 目前只有 Flash 支持图片输入，v4-pro 不支持
        case .deepSeek: "deepseek-flash"
        case .custom: ""
        }
    }

    /// 写入识别结果的服务标识；百炼沿用旧版的 qwen-direct 以保持历史记录一致
    var resultIdentifier: String {
        self == .dashScope ? "qwen-direct" : "\(rawValue)-direct"
    }
}

nonisolated struct OpenAICompatibleConfiguration: Sendable, Equatable {
    let provider: FoodAnalysisAPIProvider
    let baseURL: URL
    let model: String

    var chatCompletionsURL: URL { baseURL.appending(path: "chat/completions") }

    /// 校验并规范化用户输入：只接受 HTTPS；允许粘贴完整的 /chat/completions 地址
    init?(provider: FoodAnalysisAPIProvider, baseURL input: String, model: String) {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty,
              let baseURL = Self.normalizedBaseURL(from: input) else {
            return nil
        }
        self.provider = provider
        self.baseURL = baseURL
        self.model = trimmedModel
    }

    static func normalizedBaseURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/chat/completions") {
            path.removeLast("/chat/completions".count)
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

nonisolated struct FoodAnalysisRuntimeConfiguration: Sendable {
    let mode: FoodAnalysisConnectionMode
    let directAPI: OpenAICompatibleConfiguration?
    let proxyEndpoint: URL?
}

@MainActor
@Observable
final class FoodAnalysisSettings {
    private enum Key {
        static let mode = "GlucoMoment.FoodAnalysis.Mode"
        static let apiProvider = "GlucoMoment.FoodAnalysis.API.Provider"

        static func baseURL(_ provider: FoodAnalysisAPIProvider) -> String {
            "GlucoMoment.FoodAnalysis.API.\(provider.rawValue).BaseURL"
        }

        static func model(_ provider: FoodAnalysisAPIProvider) -> String {
            "GlucoMoment.FoodAnalysis.API.\(provider.rawValue).Model"
        }
    }

    nonisolated static let proxyServerAddress = "https://gluco.echo-sit.com"
    nonisolated static let proxyEndpoint = FoodAnalysisProxyEndpoint.analysisURL(
        from: proxyServerAddress
    )!

    var mode: FoodAnalysisConnectionMode {
        didSet { defaults?.set(mode.rawValue, forKey: Key.mode) }
    }

    /// 切换服务商时载入该服务商上次保存的地址和模型，没有则使用预设
    var apiProvider: FoodAnalysisAPIProvider {
        didSet {
            guard apiProvider != oldValue else { return }
            defaults?.set(apiProvider.rawValue, forKey: Key.apiProvider)
            loadAPIFields()
        }
    }

    var apiBaseURL: String = "" {
        didSet { persistAPIField(apiBaseURL, forKey: Key.baseURL(apiProvider)) }
    }

    var apiModel: String = "" {
        didSet { persistAPIField(apiModel, forKey: Key.model(apiProvider)) }
    }

    private let defaults: UserDefaults?
    /// 载入已保存值时不回写，避免把预设值固化到偏好里，后续版本更新预设时才能生效
    @ObservationIgnored private var isLoadingAPIFields = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 没保存过时默认用自建代理；Release 包里之前存的演示模式也改为自建代理
        let storedMode = FoodAnalysisConnectionMode(rawValue: defaults.string(forKey: Key.mode) ?? "")
        mode = storedMode.flatMap {
            FoodAnalysisConnectionMode.selectableCases.contains($0) ? $0 : nil
        } ?? .proxy
        apiProvider = FoodAnalysisAPIProvider(
            rawValue: defaults.string(forKey: Key.apiProvider) ?? ""
        ) ?? .dashScope
        loadAPIFields()
    }

    init(
        mode: FoodAnalysisConnectionMode,
        apiProvider: FoodAnalysisAPIProvider = .dashScope
    ) {
        defaults = nil
        self.mode = mode
        self.apiProvider = apiProvider
        loadAPIFields()
    }

    var directAPIConfiguration: OpenAICompatibleConfiguration? {
        OpenAICompatibleConfiguration(
            provider: apiProvider,
            baseURL: apiBaseURL,
            model: apiModel
        )
    }

    var isAPIBaseURLValid: Bool {
        OpenAICompatibleConfiguration.normalizedBaseURL(from: apiBaseURL) != nil
    }

    var isUsingProviderDefaults: Bool {
        apiBaseURL == apiProvider.defaultBaseURL && apiModel == apiProvider.defaultModel
    }

    var runtimeConfiguration: FoodAnalysisRuntimeConfiguration {
        FoodAnalysisRuntimeConfiguration(
            mode: mode,
            directAPI: directAPIConfiguration,
            proxyEndpoint: Self.proxyEndpoint
        )
    }

    /// 清除当前服务商的自定义值，回到预设（之后预设更新也会自动跟随）
    func restoreProviderDefaults() {
        defaults?.removeObject(forKey: Key.baseURL(apiProvider))
        defaults?.removeObject(forKey: Key.model(apiProvider))
        loadAPIFields()
    }

    private func persistAPIField(_ value: String, forKey key: String) {
        guard !isLoadingAPIFields else { return }
        defaults?.set(value, forKey: key)
    }

    private func loadAPIFields() {
        isLoadingAPIFields = true
        defer { isLoadingAPIFields = false }
        apiBaseURL = defaults?.string(forKey: Key.baseURL(apiProvider)) ?? apiProvider.defaultBaseURL
        apiModel = defaults?.string(forKey: Key.model(apiProvider)) ?? apiProvider.defaultModel
    }
}
