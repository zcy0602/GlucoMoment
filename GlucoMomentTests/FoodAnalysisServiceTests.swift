//
//  FoodAnalysisServiceTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@Suite("AI 食物识别配置", .serialized)
struct FoodAnalysisServiceTests {
    @Test("钥匙串按服务商分别保存、读取和删除 API Key")
    func keychainRoundTrip() async throws {
        let store = KeychainFoodAnalysisCredentialStore(service: "GlucoMomentTests.\(UUID().uuidString)")
        let dashScopeKey = "sk-test-abcdefghijklmnopqrstuvwxyz"
        let geminiKey = "AIzaSyTestKey1234567890"

        try await store.save(apiKey: dashScopeKey, for: .dashScope)
        try await store.save(apiKey: geminiKey, for: .gemini)
        #expect(try await store.apiKey(for: .dashScope) == dashScopeKey)
        #expect(try await store.apiKey(for: .gemini) == geminiKey)
        #expect(try await store.apiKey(for: .openAI) == nil)

        try await store.deleteAPIKey(for: .dashScope)
        #expect(try await store.apiKey(for: .dashScope) == nil)
        #expect(try await store.apiKey(for: .gemini) == geminiKey)
        try await store.deleteAPIKey(for: .gemini)
    }

    @Test("Key 校验不限定 sk- 前缀，但拒绝过短或含空白的值")
    func apiKeyValidation() async throws {
        let store = InMemoryFoodAnalysisCredentialStore()
        try await store.save(apiKey: "  0c7e1b2a.zhipuKeyValue  ", for: .zhipu)
        #expect(await store.apiKey(for: .zhipu) == "0c7e1b2a.zhipuKeyValue")

        await #expect(throws: CredentialStoreError.self) {
            try await store.save(apiKey: "short", for: .openAI)
        }
        await #expect(throws: CredentialStoreError.self) {
            try await store.save(apiKey: "has space inside", for: .openAI)
        }
    }

    @Test("百炼直连上传图片和用户描述，带专有参数并解析结构化结果")
    func dashScopeRequestAndResponse() async throws {
        let session = FoodAnalysisURLProtocol.makeSession(responses: [(200, try makeChatResponse())])

        let service = OpenAICompatibleFoodAnalysisService(
            apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
            configuration: try #require(OpenAICompatibleConfiguration(
                provider: .dashScope,
                baseURL: "https://example.com/v1",
                model: "qwen3.7-plus"
            )),
            session: session,
            maximumRetryCount: 0
        )
        let result = try await service.analyze(
            images: [Data([0xFF, 0xD8, 0xFF])],
            userFoodContext: "一掌鸡胸肉，无额外酱汁",
            mealPeriod: .lunch
        )

        let request = try #require(FoodAnalysisURLProtocol.capturedRequests.last)
        let body = try request.jsonBody()
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.last)
        let parts = try #require(userMessage["content"] as? [[String: Any]])
        let imagePart = try #require(parts.first)
        let imageURL = try #require(imagePart["image_url"] as? [String: String])
        let textPart = try #require(parts.last)
        let prompt = try #require(textPart["text"] as? String)

        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-abcdefghijklmnopqrstuvwxyz")
        #expect(body["model"] as? String == "qwen3.7-plus")
        #expect(body["enable_thinking"] as? Bool == false)
        #expect(imageURL["url"]?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(prompt.contains("一掌鸡胸肉，无额外酱汁"))
        #expect(prompt.contains("午餐"))
        #expect(prompt.contains("简体中文（zh-CN）"))
        #expect(result.name == "鸡胸肉蔬菜沙拉")
        #expect(result.items.count == 1)
        #expect(result.caloriesKcal == 235)
        #expect(result.provider == "qwen-direct")
    }

    @Test("多张照片按顺序放进同一条消息，文字说明在最后并注明张数")
    func multipleImagesInOneMessage() async throws {
        let session = FoodAnalysisURLProtocol.makeSession(responses: [(200, try makeChatResponse())])
        let service = OpenAICompatibleFoodAnalysisService(
            apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
            configuration: try #require(OpenAICompatibleConfiguration(
                provider: .dashScope,
                baseURL: "https://example.com/v1",
                model: "qwen3.7-plus"
            )),
            session: session,
            maximumRetryCount: 0
        )
        let images = [Data([0x01]), Data([0x02]), Data([0x03])]
        _ = try await service.analyze(images: images, userFoodContext: nil, mealPeriod: .dinner)

        let request = try #require(FoodAnalysisURLProtocol.capturedRequests.last)
        let messages = try #require(try request.jsonBody()["messages"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        let imageURLs = parts.dropLast().compactMap { ($0["image_url"] as? [String: String])?["url"] }
        let prompt = try #require(parts.last?["text"] as? String)

        #expect(parts.count == 4)
        #expect(imageURLs == images.map { "data:image/jpeg;base64,\($0.base64EncodedString())" })
        #expect(prompt.contains("共 3 张"))
    }

    @Test("照片为空或超过上限时不发请求")
    func rejectsInvalidImageCount() async throws {
        let session = FoodAnalysisURLProtocol.makeSession(responses: [])
        let service = OpenAICompatibleFoodAnalysisService(
            apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
            configuration: try #require(OpenAICompatibleConfiguration(
                provider: .dashScope,
                baseURL: "https://example.com/v1",
                model: "qwen3.7-plus"
            )),
            session: session,
            maximumRetryCount: 0
        )
        let tooMany = Array(repeating: Data([0x01]), count: FoodAnalysisImageLimit.maxImageCount + 1)

        await #expect(throws: FoodAnalysisError.self) {
            try await service.analyze(images: [], userFoodContext: nil, mealPeriod: nil)
        }
        await #expect(throws: FoodAnalysisError.self) {
            try await service.analyze(images: tooMany, userFoodContext: nil, mealPeriod: nil)
        }
        #expect(FoodAnalysisURLProtocol.capturedRequests.isEmpty)
    }

    @Test("代理请求为每张照片重复 image 字段")
    func proxyMultipartRepeatsImageField() async throws {
        let rejection = try JSONSerialization.data(withJSONObject: ["message": "测试"])
        let session = FoodAnalysisURLProtocol.makeSession(responses: [(422, rejection)])
        let service = RemoteFoodAnalysisService(
            endpoint: try #require(URL(string: "https://proxy.example.com/v1/food/analyze")),
            installationIdentifier: "test-install",
            session: session,
            maximumRetryCount: 0
        )

        await #expect(throws: FoodAnalysisError.self) {
            try await service.analyze(
                images: [Data([0x01]), Data([0x02])],
                userFoodContext: "两人合餐",
                mealPeriod: .lunch
            )
        }

        let request = try #require(FoodAnalysisURLProtocol.capturedRequests.last)
        let body = try #require(String(data: try request.bodyData(), encoding: .isoLatin1))
        #expect(body.components(separatedBy: "name=\"image\"").count - 1 == 2)
        #expect(body.contains("filename=\"meal-1.jpg\""))
        #expect(body.contains("filename=\"meal-2.jpg\""))
    }

    @Test("其他服务商只发送通用字段，不带百炼专有参数")
    func genericProviderRequestBody() async throws {
        let session = FoodAnalysisURLProtocol.makeSession(responses: [(200, try makeChatResponse())])
        let service = OpenAICompatibleFoodAnalysisService(
            apiKey: "AIzaSyTestKey1234567890",
            configuration: try #require(OpenAICompatibleConfiguration(
                provider: .gemini,
                baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                model: "gemini-test"
            )),
            session: session,
            maximumRetryCount: 0
        )
        let result = try await service.analyze(
            images: [Data([0xFF, 0xD8, 0xFF])],
            userFoodContext: nil,
            mealPeriod: nil
        )

        let request = try #require(FoodAnalysisURLProtocol.capturedRequests.last)
        let body = try request.jsonBody()
        #expect(
            request.url?.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        )
        #expect(body["model"] as? String == "gemini-test")
        #expect(body["response_format"] != nil)
        #expect(body["enable_thinking"] == nil)
        #expect(body["temperature"] == nil)
        #expect(body["max_completion_tokens"] == nil)
        #expect(result.provider == "gemini-direct")
        #expect(result.model == "gemini-test")
    }

    @Test("服务商拒绝 JSON 模式时去掉 response_format 重试一次")
    func jsonModeFallback() async throws {
        let rejection = try JSONSerialization.data(withJSONObject: [
            "error": ["message": "response_format is not supported"]
        ])
        let session = FoodAnalysisURLProtocol.makeSession(responses: [
            (400, rejection),
            (200, try makeChatResponse())
        ])
        let service = OpenAICompatibleFoodAnalysisService(
            apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
            configuration: try #require(OpenAICompatibleConfiguration(
                provider: .custom,
                baseURL: "https://llm.example.com/v1",
                model: "vision-model"
            )),
            session: session,
            maximumRetryCount: 0
        )
        let result = try await service.analyze(
            images: [Data([0xFF, 0xD8, 0xFF])],
            userFoodContext: nil,
            mealPeriod: nil
        )

        #expect(FoodAnalysisURLProtocol.capturedRequests.count == 2)
        #expect(try FoodAnalysisURLProtocol.capturedRequests[0].jsonBody()["response_format"] != nil)
        #expect(try FoodAnalysisURLProtocol.capturedRequests[1].jsonBody()["response_format"] == nil)
        #expect(result.name == "鸡胸肉蔬菜沙拉")
    }

    @Test("连接测试发送图片，模型认不出颜色时提示可能不支持视觉")
    func connectionTestDetectsVisionSupport() async throws {
        let configuration = try #require(OpenAICompatibleConfiguration(
            provider: .openAI,
            baseURL: "https://api.example.com/v1",
            model: "text-only"
        ))

        let okSession = FoodAnalysisURLProtocol.makeSession(responses: [(200, try makeChatResponse(content: "红色"))])
        let message = try await OpenAICompatibleFoodAnalysisService(
            apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
            configuration: configuration,
            session: okSession
        ).testConnection()
        #expect(message.contains("text-only"))
        let parts = try #require(
            (try FoodAnalysisURLProtocol.capturedRequests[0].jsonBody()["messages"] as? [[String: Any]])?
                .first?["content"] as? [[String: Any]]
        )
        #expect(parts.first?["type"] as? String == "image_url")

        let blindSession = FoodAnalysisURLProtocol.makeSession(
            responses: [(200, try makeChatResponse(content: "我无法查看图片"))]
        )
        await #expect(throws: FoodAnalysisError.self) {
            try await OpenAICompatibleFoodAnalysisService(
                apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
                configuration: configuration,
                session: blindSession
            ).testConnection()
        }
    }

    @Test("模型列表去重并排序")
    func availableModelsListing() async throws {
        let list = try JSONSerialization.data(withJSONObject: [
            "object": "list",
            "data": [["id": "model-b"], ["id": "model-a"], ["id": "model-b"]]
        ])
        let session = FoodAnalysisURLProtocol.makeSession(responses: [(200, list)])
        let models = try await OpenAICompatibleFoodAnalysisService.availableModels(
            apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
            baseURL: try #require(URL(string: "https://api.example.com/v1")),
            session: session
        )

        #expect(models == ["model-a", "model-b"])
        #expect(FoodAnalysisURLProtocol.capturedRequests.last?.url?.absoluteString == "https://api.example.com/v1/models")
    }

    @Test("API 地址只接受 HTTPS，并兼容粘贴完整接口地址")
    func directAPIBaseURLNormalization() {
        #expect(
            OpenAICompatibleConfiguration.normalizedBaseURL(
                from: " https://api.example.com/v1/chat/completions/ "
            )?.absoluteString == "https://api.example.com/v1"
        )
        #expect(
            OpenAICompatibleConfiguration.normalizedBaseURL(from: "https://api.example.com/v1/")?
                .absoluteString == "https://api.example.com/v1"
        )
        #expect(OpenAICompatibleConfiguration.normalizedBaseURL(from: "http://api.example.com/v1") == nil)
        #expect(OpenAICompatibleConfiguration.normalizedBaseURL(from: "api.example.com") == nil)
        #expect(OpenAICompatibleConfiguration(
            provider: .custom,
            baseURL: "https://api.example.com/v1",
            model: "   "
        ) == nil)
    }

    @MainActor
    @Test("服务商的地址和模型分别保存，未修改时跟随预设")
    func directAPISettingsPersistence() throws {
        let suiteName = "GlucoMomentTests.APISettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = FoodAnalysisSettings(defaults: defaults)
        #expect(settings.apiProvider == .dashScope)
        #expect(settings.apiModel == FoodAnalysisAPIProvider.dashScope.defaultModel)
        // 只载入预设时不应写入偏好
        #expect(defaults.string(forKey: "GlucoMoment.FoodAnalysis.API.dashScope.Model") == nil)

        settings.apiProvider = .openAI
        settings.apiModel = "my-vision-model"
        settings.apiProvider = .zhipu
        #expect(settings.apiBaseURL == FoodAnalysisAPIProvider.zhipu.defaultBaseURL)

        let restored = FoodAnalysisSettings(defaults: defaults)
        #expect(restored.apiProvider == .zhipu)
        restored.apiProvider = .openAI
        #expect(restored.apiModel == "my-vision-model")
        #expect(restored.isUsingProviderDefaults == false)

        restored.restoreProviderDefaults()
        #expect(restored.apiModel == FoodAnalysisAPIProvider.openAI.defaultModel)
        #expect(restored.isUsingProviderDefaults)
    }

    @MainActor
    @Test("升级前保存的 directQwen 模式映射为自定义 API")
    func legacyModeMigration() throws {
        let suiteName = "GlucoMomentTests.LegacyMode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("directQwen", forKey: "GlucoMoment.FoodAnalysis.Mode")

        let settings = FoodAnalysisSettings(defaults: defaults)
        #expect(settings.mode == .directAPI)
        #expect(settings.apiProvider == .dashScope)
        #expect(settings.directAPIConfiguration?.chatCompletionsURL.absoluteString
            == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    @MainActor
    @Test("模式保存在普通偏好中且代理使用预置地址")
    func settingsPersistence() throws {
        let suiteName = "GlucoMomentTests.Settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = FoodAnalysisSettings(defaults: defaults)
        settings.mode = .proxy

        let restored = FoodAnalysisSettings(defaults: defaults)
        #expect(restored.mode == .proxy)
        #expect(
            restored.runtimeConfiguration.proxyEndpoint?.absoluteString
                == "https://gluco.echo-sit.com/v1/food/analyze"
        )
        #expect(defaults.dictionaryRepresentation().values.contains { value in
            String(describing: value).contains("sk-")
        } == false)
    }

    @MainActor
    @Test("代理根地址会自动补全分析路径")
    func proxyRootURLNormalization() throws {
        let endpoint = try #require(
            FoodAnalysisProxyEndpoint.analysisURL(from: " https://gluco.echo-sit.com/ ")
        )

        #expect(endpoint.absoluteString == "https://gluco.echo-sit.com/v1/food/analyze")
        #expect(
            FoodAnalysisProxyEndpoint.healthURL(from: endpoint)?.absoluteString
                == "https://gluco.echo-sit.com/health"
        )
    }

    @MainActor
    @Test("完整代理接口地址保持兼容并移除尾部斜杠")
    func fullProxyURLNormalization() {
        #expect(
            FoodAnalysisProxyEndpoint.analysisURL(
                from: "https://example.com/v1/food/analyze/"
            )?.absoluteString
                == "https://example.com/v1/food/analyze"
        )
    }

    private func makeChatResponse(content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
    }

    private func makeChatResponse() throws -> Data {
        let payload: [String: Any] = [
            "mealName": "鸡胸肉蔬菜沙拉",
            "overallConfidence": 0.8,
            "glucoseImpact": "低",
            "score": 86,
            "items": [[
                "name": "鸡胸肉",
                "portionDescription": "一掌大小",
                "estimatedGramsMin": 120,
                "estimatedGramsMax": 140,
                "caloriesMin": 220,
                "caloriesMax": 250,
                "carbsMin": 0,
                "carbsMax": 0,
                "proteinMin": 35,
                "proteinMax": 42,
                "fatMin": 5,
                "fatMax": 8,
                "fiberMin": 0,
                "fiberMax": 0,
                "confidence": 0.9,
                "evidence": "图片和用户描述",
                "uncertainties": ["烹饪用油未知"]
            ]],
            "followUpQuestions": ["是否使用烹饪油？"],
            "suggestions": ["确认用油量后估算更准确。"],
            "uncertainties": ["隐藏配料不可见"]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadString = try #require(String(data: payloadData, encoding: .utf8))
        return try makeChatResponse(content: payloadString)
    }
}

/// 按顺序返回预设的响应，并记录收到的请求；套件串行执行，静态状态不会互相干扰
private final class FoodAnalysisURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(statusCode: Int, data: Data)] = []
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func makeSession(responses: [(Int, Data)]) -> URLSession {
        self.responses = responses.map { (statusCode: $0.0, data: $0.1) }
        capturedRequests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FoodAnalysisURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(request)
        let next = Self.responses.isEmpty ? (statusCode: 500, data: Data()) : Self.responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func bodyData() throws -> Data {
        try #require(httpBody ?? httpBodyStream?.readAllData())
    }

    func jsonBody() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
    }
}

private extension InputStream {
    func readAllData() -> Data? {
        open()
        defer { close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while hasBytesAvailable {
            let count = read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}
