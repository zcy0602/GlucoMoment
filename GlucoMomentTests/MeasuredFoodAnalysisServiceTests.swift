//
//  MeasuredFoodAnalysisServiceTests.swift
//  GlucoMomentTests
//

import Foundation
import Testing
@testable import GlucoMoment

@Suite("LiDAR 两段式识别服务", .serialized)
struct MeasuredFoodAnalysisServiceTests {
    // MARK: - 检测结果校验

    @Test("检测结果会丢弃无效框并修复越界引用")
    func detectionValidation() throws {
        let payload = try decodeDetection([
            "mealName": "红烧肉盖饭",
            "containers": [
                ["index": 0, "type": "shallowBowl", "box": [100, 200, 900, 800]],
                ["index": 1, "type": "spaceship", "box": [0, 0, 300, 300]]
            ],
            "items": [
                ["index": 0, "name": "米饭", "category": "staple", "box": [150, 250, 850, 750], "containerIndex": 0],
                ["index": 1, "name": "红烧肉", "category": "unknown", "box": [400, 400, 600, 600],
                 "containerIndex": 9, "layeredOnIndex": 0],
                ["index": 2, "name": "无效框", "box": [500, 500, 502, 900]],
                ["index": 3, "name": " ", "box": [0, 0, 500, 500]]
            ]
        ])

        let result = try payload.makeResult(provider: "test", model: "m", promptVersion: "v")
        #expect(result.items.map(\.name) == ["米饭", "红烧肉"])
        #expect(result.containers.map(\.type) == [.shallowBowl, .flatPlate])

        let rice = try #require(result.item(index: 0))
        #expect(rice.containerIndex == 0)
        #expect(rice.category == .staple)
        #expect(abs(rice.box.minX - 0.15) < 1e-9)
        #expect(abs(rice.box.maxY - 0.75) < 1e-9)

        let pork = try #require(result.item(index: 1))
        #expect(pork.category == .other)
        #expect(pork.containerIndex == nil)
        #expect(pork.layeredOnIndex == 0)
        #expect(pork.layerThicknessCentimeters == 0.5...2.0)
    }

    @Test("互相叠放的引用只保留一个")
    func detectionBreaksLayerCycles() throws {
        let payload = try decodeDetection([
            "mealName": "拼盘",
            "items": [
                ["index": 0, "name": "A", "box": [0, 0, 500, 500], "layeredOnIndex": 1,
                 "layerThicknessCmMin": 1, "layerThicknessCmMax": 2],
                ["index": 1, "name": "B", "box": [100, 100, 600, 600], "layeredOnIndex": 0],
                ["index": 2, "name": "C", "box": [100, 100, 600, 600], "layeredOnIndex": 2]
            ]
        ])

        let result = try payload.makeResult(provider: "test", model: "m", promptVersion: "v")
        let layered = result.items.filter { $0.layeredOnIndex != nil }
        #expect(layered.count == 1)
        #expect(result.item(index: 2)?.layeredOnIndex == nil)
        #expect(result.item(index: 2)?.layerThicknessCentimeters == nil)
    }

    @Test("没有有效食物时视为无效响应")
    func detectionRequiresItems() throws {
        let payload = try decodeDetection([
            "mealName": "空盘",
            "items": [["index": 0, "name": "碎屑", "box": [0, 0, 1, 1]]]
        ])

        #expect(throws: FoodAnalysisError.self) {
            try payload.makeResult(provider: "test", model: "m", promptVersion: "v")
        }
    }

    // MARK: - 直连 Qwen

    @Test("直连检测请求要求返回边界框并解析结果")
    func qwenDetection() async throws {
        let session = MeasuredStubURLProtocol.makeSession(responses: [
            try makeChatResponse([
                "mealName": "米饭",
                "containers": [["index": 0, "type": "deepBowl", "box": [100, 100, 900, 900]]],
                "items": [["index": 0, "name": "米饭", "category": "staple", "box": [200, 200, 800, 800],
                           "containerIndex": 0, "densityMin": 0.7, "densityMax": 0.9, "confidence": 0.9]]
            ])
        ])
        let service = QwenFoodAnalysisService(
            apiKey: "sk-test",
            endpoint: URL(string: "https://example.com/chat/completions")!,
            session: session,
            maximumRetryCount: 0
        )

        let result = try await service.detectFoods(imageData: Data([0xFF, 0xD8]), userFoodContext: nil, mealPeriod: .dinner)

        let body = try MeasuredStubURLProtocol.jsonBody(at: 0)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let systemPrompt = try #require(messages.first?["content"] as? String)
        #expect(systemPrompt.contains("0～1000"))
        #expect(systemPrompt.contains("layeredOnIndex"))
        #expect(result.promptVersion == QwenFoodAnalysisService.detectionPromptVersion)
        #expect(result.containers.first?.type == .deepBowl)
        #expect(result.items.first?.densityRange == 0.7...0.9)
    }

    @Test("直连估算请求携带实测数据，结果挂载测量摘要")
    func qwenMeasuredEstimate() async throws {
        let detection = makeDetection()
        let measurements = makeMeasurements(detection: detection)
        let session = MeasuredStubURLProtocol.makeSession(responses: [
            try makeChatResponse(makeEstimatePayload(porkGrams: 400))
        ])
        let service = QwenFoodAnalysisService(
            apiKey: "sk-test",
            endpoint: URL(string: "https://example.com/chat/completions")!,
            session: session,
            maximumRetryCount: 0
        )

        let result = try await service.estimateNutrition(
            imageData: Data([0xFF, 0xD8]),
            detection: detection,
            measurements: measurements,
            userFoodContext: "少油",
            mealPeriod: .lunch
        )

        let body = try MeasuredStubURLProtocol.jsonBody(at: 0)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        let text = try #require(parts.last?["text"] as? String)
        #expect(text.contains("<lidar_measurements>"))
        #expect(text.contains("\"measuredGrams\":165"))
        #expect(text.contains("少油"))

        #expect(result.measurementMethod == .lidarMeasured)
        #expect(result.promptVersion == QwenFoodAnalysisService.measuredPromptVersion)

        // 模型把条目顺序调换了，仍应按 itemIndex 匹配。
        let rice = try #require(result.items.first { $0.name == "米饭" })
        let pork = try #require(result.items.first { $0.name == "红烧肉" })
        #expect(rice.id == detection.items[0].id)
        #expect(rice.measurement?.measuredGrams == 165)
        #expect(pork.id == detection.items[1].id)
        #expect(pork.uncertainties.contains { $0.contains("LiDAR 实测区间") })
        #expect(!rice.uncertainties.contains { $0.contains("LiDAR 实测区间") })
    }

    // MARK: - 代理服务器

    @Test("代理两段式接口地址由分析地址推导")
    func proxySiblingURLs() throws {
        let root = try #require(URL(string: "http://106.52.20.70:8787/v1/food/analyze"))
        #expect(FoodAnalysisProxyEndpoint.detectionURL(from: root)?.absoluteString == "http://106.52.20.70:8787/v1/food/detect")
        #expect(FoodAnalysisProxyEndpoint.measuredEstimateURL(from: root)?.absoluteString == "http://106.52.20.70:8787/v1/food/estimate")

        let prefixed = try #require(URL(string: "https://example.com/api/v1/food/analyze"))
        #expect(FoodAnalysisProxyEndpoint.detectionURL(from: prefixed)?.absoluteString == "https://example.com/api/v1/food/detect")

        let custom = try #require(URL(string: "https://example.com/custom/analyze"))
        #expect(FoodAnalysisProxyEndpoint.detectionURL(from: custom)?.absoluteString == "https://example.com/v1/food/detect")
    }

    @Test("代理检测与估算请求使用新接口并上传实测数据")
    func proxyMeasuredFlow() async throws {
        let detectionResponse: [String: Any] = [
            "provider": "proxy-qwen",
            "model": "qwen3.7-plus",
            "promptVersion": "food-detect-v1",
            "mealName": "红烧肉盖饭",
            "items": [["index": 0, "name": "米饭", "category": "staple", "box": [100, 100, 900, 900]]]
        ]
        var estimateResponse = makeEstimatePayload(porkGrams: 60)
        estimateResponse["provider"] = "proxy-qwen"
        estimateResponse["model"] = "qwen3.7-plus"
        estimateResponse["promptVersion"] = "food-measured-v1"

        let session = MeasuredStubURLProtocol.makeSession(responses: [
            try JSONSerialization.data(withJSONObject: detectionResponse),
            try JSONSerialization.data(withJSONObject: estimateResponse)
        ])
        let service = RemoteFoodAnalysisService(
            endpoint: URL(string: "https://example.com/v1/food/analyze")!,
            installationIdentifier: "install-1",
            session: session,
            maximumRetryCount: 0
        )

        let detection = try await service.detectFoods(imageData: Data([0xFF]), userFoodContext: nil, mealPeriod: nil)
        #expect(detection.provider == "proxy-qwen")
        #expect(detection.items.count == 1)

        let fixture = makeDetection()
        let result = try await service.estimateNutrition(
            imageData: Data([0xFF]),
            detection: fixture,
            measurements: makeMeasurements(detection: fixture),
            userFoodContext: nil,
            mealPeriod: .lunch
        )

        let detectRequest = try #require(MeasuredStubURLProtocol.request(at: 0))
        let estimateRequest = try #require(MeasuredStubURLProtocol.request(at: 1))
        #expect(detectRequest.url?.path == "/v1/food/detect")
        #expect(estimateRequest.url?.path == "/v1/food/estimate")
        #expect(estimateRequest.value(forHTTPHeaderField: "X-Install-Id") == "install-1")

        let detectBody = try #require(MeasuredStubURLProtocol.bodyString(at: 0))
        let estimateBody = try #require(MeasuredStubURLProtocol.bodyString(at: 1))
        #expect(detectBody.contains("name=\"schemaVersion\"\r\n\r\n2\r\n"))
        #expect(estimateBody.contains("name=\"measurements\""))
        #expect(estimateBody.contains("\"containerType\":\"shallowBowl\""))
        #expect(result.measurementMethod == .lidarMeasured)
        #expect(result.items.allSatisfy { $0.measurement != nil })
    }

    // MARK: - 演示模式

    @Test("演示模式按实测克重换算营养")
    func demoMeasuredEstimate() async throws {
        let service = DemoFoodAnalysisService()
        let detection = try await service.detectFoods(imageData: Data(), userFoodContext: nil, mealPeriod: nil)
        let measurements = makeMeasurements(detection: detection)

        let result = try await service.estimateNutrition(
            imageData: Data(),
            detection: detection,
            measurements: measurements,
            userFoodContext: nil,
            mealPeriod: nil
        )

        let rice = try #require(result.items.first { $0.name == "米饭" })
        #expect(rice.estimatedGrams == 165)
        #expect(abs(rice.carbohydratesGrams - 165 * 0.259) < 1e-9)
        #expect(rice.measurement != nil)
        #expect(result.measurementMethod == .lidarMeasured)
    }
}

// MARK: - 测试数据

private func decodeDetection(_ object: [String: Any]) throws -> FoodDetectionPayloadDTO {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(FoodDetectionPayloadDTO.self, from: data)
}

private func makeChatResponse(_ payload: [String: Any]) throws -> Data {
    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    let payloadString = try #require(String(data: payloadData, encoding: .utf8))
    return try JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": payloadString]]]
    ])
}

private func makeDetection() -> FoodDetectionResult {
    FoodDetectionResult(
        mealName: "红烧肉盖饭",
        items: [
            FoodDetectedItem(
                index: 0,
                name: "米饭",
                category: .staple,
                box: FoodBoundingBox(minX: 0.2, minY: 0.2, maxX: 0.8, maxY: 0.8),
                containerIndex: 0,
                confidence: 0.9
            ),
            FoodDetectedItem(
                index: 1,
                name: "红烧肉",
                category: .meat,
                box: FoodBoundingBox(minX: 0.4, minY: 0.4, maxX: 0.6, maxY: 0.6),
                containerIndex: 0,
                layeredOnIndex: 0,
                layerThicknessCentimeters: 1...2,
                confidence: 0.8
            )
        ],
        containers: [
            FoodDetectedContainer(index: 0, type: .shallowBowl, box: FoodBoundingBox(minX: 0.1, minY: 0.1, maxX: 0.9, maxY: 0.9))
        ],
        uncertainties: [],
        provider: "test",
        model: "m",
        promptVersion: "v"
    )
}

private func makeMeasurements(detection: FoodDetectionResult) -> [FoodMeasuredItem] {
    detection.items.map { item in
        let isRice = item.index == 0
        return FoodMeasuredItem(
            detection: item,
            measurement: FoodItemMeasurement(
                method: .lidarMeasured,
                volumeMilliliters: isRice ? 200 : 80,
                volumeMinMilliliters: isRice ? 180 : 60,
                volumeMaxMilliliters: isRice ? 230 : 100,
                footprintAreaSquareCentimeters: isRice ? 120 : 30,
                meanHeightCentimeters: isRice ? 1.7 : 2.7,
                coverage: 0.9,
                containerType: .shallowBowl,
                densityGramsPerMilliliter: isRice ? 0.825 : 0.875,
                densityMinGramsPerMilliliter: isRice ? 0.75 : 0.75,
                densityMaxGramsPerMilliliter: isRice ? 0.9 : 1.0,
                densitySource: .localTable,
                measuredGrams: isRice ? 165 : 70,
                measuredGramsMin: isRice ? 135 : 45,
                measuredGramsMax: isRice ? 207 : 100,
                notes: []
            ),
            layeredOnName: item.layeredOnIndex == 0 ? "米饭" : nil
        )
    }
}

/// 估算阶段响应：故意把红烧肉放在第一位，用于验证按 itemIndex 匹配。
private func makeEstimatePayload(porkGrams: Double) -> [String: Any] {
    func item(index: Int, name: String, grams: Double) -> [String: Any] {
        [
            "itemIndex": index,
            "name": name,
            "portionDescription": "实测",
            "estimatedGramsMin": grams,
            "estimatedGramsMax": grams,
            "caloriesMin": 100,
            "caloriesMax": 120,
            "carbsMin": 10,
            "carbsMax": 12,
            "proteinMin": 5,
            "proteinMax": 6,
            "fatMin": 1,
            "fatMax": 2,
            "fiberMin": 0,
            "fiberMax": 1,
            "confidence": 0.8,
            "evidence": "实测数据",
            "uncertainties": []
        ]
    }

    return [
        "mealName": "红烧肉盖饭",
        "overallConfidence": 0.8,
        "glucoseImpact": "中等",
        "score": 70,
        "items": [item(index: 1, name: "红烧肉", grams: porkGrams), item(index: 0, name: "米饭", grams: 165)],
        "followUpQuestions": [],
        "suggestions": [],
        "uncertainties": []
    ]
}

/// 按顺序返回预设响应并记录请求。
private final class MeasuredStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [Data] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func makeSession(responses: [Data]) -> URLSession {
        Self.responses = responses
        requests = []
        bodies = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeasuredStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func request(at index: Int) -> URLRequest? {
        requests.indices.contains(index) ? requests[index] : nil
    }

    static func bodyString(at index: Int) -> String? {
        guard bodies.indices.contains(index) else { return nil }
        return String(decoding: bodies[index], as: UTF8.self)
    }

    static func jsonBody(at index: Int) throws -> [String: Any] {
        let data = try #require(bodies.indices.contains(index) ? bodies[index] : nil)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let index = Self.requests.count
        Self.requests.append(request)
        Self.bodies.append(request.httpBody ?? request.httpBodyStream.flatMap(Self.readAll) ?? Data())

        let data = Self.responses.indices.contains(index) ? Self.responses[index] : Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}
