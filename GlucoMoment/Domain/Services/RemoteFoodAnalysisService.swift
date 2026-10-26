//
//  RemoteFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

actor RemoteFoodAnalysisService: FoodAnalysisService {
    private let endpoint: URL
    private let installationIdentifier: String
    private let session: URLSession
    private let maximumRetryCount: Int

    init(
        endpoint: URL,
        installationIdentifier: String,
        session: URLSession = .shared,
        maximumRetryCount: Int = 2
    ) {
        self.endpoint = endpoint
        self.installationIdentifier = installationIdentifier
        self.session = session
        self.maximumRetryCount = maximumRetryCount
    }

    func analyze(
        images: [Data],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        let data = try await post(
            to: endpoint,
            fields: [
                "mealPeriod": mealPeriod?.rawValue ?? "",
                "userFoodContext": userFoodContext ?? ""
            ],
            images: images
        )

        do {
            return try JSONDecoder().decode(FoodAnalysisProxyResponseDTO.self, from: data).makeResult()
        } catch {
            throw FoodAnalysisError.invalidResponse
        }
    }

    func correct(_ request: FoodCorrectionRequest) async throws -> FoodCorrectionOutcome {
        guard let correctionURL = FoodAnalysisProxyEndpoint.correctionURL(from: endpoint) else {
            throw FoodAnalysisError.invalidEndpoint
        }

        let data = try await post(
            to: correctionURL,
            fields: [
                "mealPeriod": request.mealPeriod?.rawValue ?? "",
                "userFoodContext": request.userFoodContext ?? "",
                "currentResult": FoodCorrectionRecord.recordJSON(for: request.current),
                "history": FoodCorrectionRecord.historyJSON(request.history),
                "instruction": request.instruction
            ],
            images: request.images
        )

        let patch: FoodCorrectionPatch
        do {
            patch = try JSONDecoder().decode(FoodCorrectionPayloadDTO.self, from: data).makePatch()
        } catch {
            throw FoodAnalysisError.invalidResponse
        }
        return try patch.apply(to: request.current)
    }

    /// 发送 multipart 请求并返回成功响应的原始数据；重试时沿用同一个请求 ID
    private func post(to url: URL, fields: [String: String], images: [Data]) async throws -> Data {
        let requestID = UUID()
        var lastError: (any Error)?

        for attempt in 0...maximumRetryCount {
            do {
                return try await performRequest(
                    url: url,
                    requestID: requestID,
                    fields: fields,
                    images: images
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as FoodAnalysisError {
                lastError = error
                guard error.isRetryable, attempt < maximumRetryCount else { throw error }
            } catch let error as URLError {
                lastError = error
                guard attempt < maximumRetryCount else {
                    throw FoodAnalysisError.networkUnavailable
                }
            }

            let delay = 400 * (1 << attempt) + Int.random(in: 0...180)
            try await Task.sleep(for: .milliseconds(delay))
        }

        throw lastError ?? FoodAnalysisError.invalidResponse
    }

    private func performRequest(
        url: URL,
        requestID: UUID,
        fields: [String: String],
        images: [Data]
    ) async throws -> Data {
        let boundary = "GlucoMoment-\(requestID.uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 最多 6 张照片时模型响应更慢，与直连 API 保持同样的 60 秒
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-Id")
        request.setValue(installationIdentifier, forHTTPHeaderField: "X-Install-Id")
        request.httpBody = MultipartFormData.makeBody(
            boundary: boundary,
            fields: fields.merging([
                "requestId": requestID.uuidString,
                "schemaVersion": "1",
                "locale": "zh-CN"
            ]) { current, _ in current },
            images: images
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodAnalysisError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(FoodAnalysisErrorPayload.self, from: data)
            throw FoodAnalysisError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: payload?.message
            )
        }
        return data
    }
}

private nonisolated struct FoodAnalysisErrorPayload: Decodable {
    let message: String?
}

private nonisolated enum MultipartFormData {
    static func makeBody(
        boundary: String,
        fields: [String: String],
        images: [Data]
    ) -> Data {
        var body = Data()

        for key in fields.keys.sorted() {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendUTF8("\(fields[key] ?? "")\r\n")
        }

        // 多张照片重复使用 image 字段，代理按出现顺序读取
        for (index, imageData) in images.enumerated() {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"image\"; filename=\"meal-\(index + 1).jpg\"\r\n")
            body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            body.appendUTF8("\r\n")
        }
        body.appendUTF8("--\(boundary)--\r\n")
        return body
    }
}

private nonisolated extension Data {
    mutating func appendUTF8(_ string: String) {
        append(contentsOf: string.utf8)
    }
}

// MARK: - 近期复盘

extension RemoteFoodAnalysisService: MealReviewService {
    /// 与识别、修正共用 multipart 和重试；数据放在 payload 字段，不带照片
    func review(_ payload: MealReviewPayload) async throws -> MealReviewDraft {
        guard let reviewURL = FoodAnalysisProxyEndpoint.reviewURL(from: endpoint) else {
            throw FoodAnalysisError.invalidEndpoint
        }

        let data = try await post(
            to: reviewURL,
            fields: ["payload": try MealReviewPrompt.payloadJSON(payload)],
            images: []
        )
        do {
            return try JSONDecoder().decode(MealReviewResponseDTO.self, from: data)
                .makeDraft(provider: "proxy", model: "unknown")
        } catch {
            throw FoodAnalysisError.invalidResponse
        }
    }
}
