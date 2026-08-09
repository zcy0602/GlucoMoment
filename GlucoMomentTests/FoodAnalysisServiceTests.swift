//
//  FoodAnalysisServiceTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@Suite("AI 食物识别配置", .serialized)
struct FoodAnalysisServiceTests {
    @Test("钥匙串可以保存、读取和删除 API Key")
    func keychainRoundTrip() async throws {
        let store = KeychainFoodAnalysisCredentialStore(service: "GlucoMomentTests.\(UUID().uuidString)")
        let key = "sk-test-abcdefghijklmnopqrstuvwxyz"

        try await store.save(apiKey: key)
        #expect(try await store.apiKey() == key)

        try await store.deleteAPIKey()
        #expect(try await store.apiKey() == nil)
    }

    @Test("直连请求上传图片和用户描述并解析结构化结果")
    func directQwenRequestAndResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FoodAnalysisURLProtocol.self]
        let session = URLSession(configuration: configuration)
        FoodAnalysisURLProtocol.responseData = try makeQwenResponse()
        FoodAnalysisURLProtocol.capturedRequest = nil

        let service = QwenFoodAnalysisService(
            apiKey: "sk-test-abcdefghijklmnopqrstuvwxyz",
            endpoint: URL(string: "https://example.com/chat/completions")!,
            session: session,
            maximumRetryCount: 0
        )
        let result = try await service.analyze(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            userFoodContext: "一掌鸡胸肉，无额外酱汁",
            mealPeriod: .lunch
        )

        let request = try #require(FoodAnalysisURLProtocol.capturedRequest)
        let bodyData = try #require(request.httpBody ?? request.httpBodyStream?.readAllData())
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.last)
        let parts = try #require(userMessage["content"] as? [[String: Any]])
        let imagePart = try #require(parts.first)
        let imageURL = try #require(imagePart["image_url"] as? [String: String])
        let textPart = try #require(parts.last)
        let prompt = try #require(textPart["text"] as? String)

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

    @MainActor
    @Test("模式和代理地址保存在普通偏好中但不包含 API Key")
    func settingsPersistence() throws {
        let suiteName = "GlucoMomentTests.Settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = FoodAnalysisSettings(defaults: defaults)
        settings.mode = .proxy
        settings.proxyEndpointString = "https://example.com/v1/food/analyze"

        let restored = FoodAnalysisSettings(defaults: defaults)
        #expect(restored.mode == .proxy)
        #expect(restored.validatedProxyEndpoint?.absoluteString == "https://example.com/v1/food/analyze")
        #expect(defaults.dictionaryRepresentation().values.contains { value in
            String(describing: value).contains("sk-")
        } == false)
    }

    @MainActor
    @Test("代理根地址会自动补全分析路径")
    func proxyRootURLNormalization() throws {
        let settings = FoodAnalysisSettings(
            mode: .proxy,
            proxyEndpointString: " http://106.52.20.70:8787/ "
        )

        let endpoint = try #require(settings.validatedProxyEndpoint)
        #expect(endpoint.absoluteString == "http://106.52.20.70:8787/v1/food/analyze")
        #expect(settings.runtimeConfiguration.proxyEndpoint == endpoint)
        #expect(
            FoodAnalysisProxyEndpoint.healthURL(from: endpoint)?.absoluteString
                == "http://106.52.20.70:8787/health"
        )
    }

    @MainActor
    @Test("完整代理接口地址保持兼容并移除尾部斜杠")
    func fullProxyURLNormalization() {
        let settings = FoodAnalysisSettings(
            mode: .proxy,
            proxyEndpointString: "https://example.com/v1/food/analyze/"
        )

        #expect(
            settings.validatedProxyEndpoint?.absoluteString
                == "https://example.com/v1/food/analyze"
        )
    }

    private func makeQwenResponse() throws -> Data {
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
        return try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": payloadString]]]
        ])
    }
}

private final class FoodAnalysisURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var capturedRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
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
