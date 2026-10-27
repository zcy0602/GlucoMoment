//
//  RemoteFoodAnalysisService.swift
//  GlucoMoment
//

import Foundation

actor RemoteFoodAnalysisService: FoodAnalysisService, MeasuredFoodAnalysisService {
    /// 代理服务器的分析接口地址（`/v1/food/analyze`），两段式接口由此推导。
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
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        let requestID = UUID()
        let data = try await withRetry {
            try await self.postMultipart(
                to: self.endpoint,
                requestID: requestID,
                schemaVersion: "1",
                fields: self.commonFields(userFoodContext: userFoodContext, mealPeriod: mealPeriod),
                imageData: imageData
            )
        }

        do {
            return try JSONDecoder().decode(FoodAnalysisProxyResponseDTO.self, from: data).makeResult()
        } catch {
            throw FoodAnalysisError.invalidResponse
        }
    }

    func detectFoods(
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodDetectionResult {
        guard let url = FoodAnalysisProxyEndpoint.detectionURL(from: endpoint) else {
            throw FoodAnalysisError.invalidEndpoint
        }

        let requestID = UUID()
        let data = try await withRetry {
            try await self.postMultipart(
                to: url,
                requestID: requestID,
                schemaVersion: "2",
                fields: self.commonFields(userFoodContext: userFoodContext, mealPeriod: mealPeriod),
                imageData: imageData
            )
        }

        do {
            return try JSONDecoder().decode(FoodDetectionProxyResponseDTO.self, from: data).makeResult()
        } catch let error as FoodAnalysisError {
            throw error
        } catch {
            throw FoodAnalysisError.invalidResponse
        }
    }

    func estimateNutrition(
        imageData: Data,
        detection: FoodDetectionResult,
        measurements: [FoodMeasuredItem],
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        guard let url = FoodAnalysisProxyEndpoint.measuredEstimateURL(from: endpoint) else {
            throw FoodAnalysisError.invalidEndpoint
        }

        var fields = commonFields(userFoodContext: userFoodContext, mealPeriod: mealPeriod)
        fields["measurements"] = try FoodMeasurementReportDTO(
            mealName: detection.mealName,
            measurements: measurements
        ).jsonString()

        let requestID = UUID()
        let data = try await withRetry {
            try await self.postMultipart(
                to: url,
                requestID: requestID,
                schemaVersion: "2",
                fields: fields,
                imageData: imageData
            )
        }

        do {
            let response = try JSONDecoder().decode(FoodAnalysisProxyResponseDTO.self, from: data)
            return FoodMeasuredResultAssembler.assemble(
                try response.makeResult(),
                itemIndices: response.items.map(\.itemIndex),
                measurements: measurements
            )
        } catch let error as FoodAnalysisError {
            throw error
        } catch {
            throw FoodAnalysisError.invalidResponse
        }
    }

    private func commonFields(userFoodContext: String?, mealPeriod: MealPeriod?) -> [String: String] {
        [
            "locale": "zh-CN",
            "mealPeriod": mealPeriod?.rawValue ?? "",
            "userFoodContext": userFoodContext ?? ""
        ]
    }

    private func withRetry<Result: Sendable>(
        _ operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        var lastError: (any Error)?

        for attempt in 0...maximumRetryCount {
            do {
                return try await operation()
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

    /// 以 multipart/form-data 上传图片和字段，返回 2xx 响应体。
    private func postMultipart(
        to url: URL,
        requestID: UUID,
        schemaVersion: String,
        fields: [String: String],
        imageData: Data
    ) async throws -> Data {
        let boundary = "GlucoMoment-\(requestID.uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-Id")
        request.setValue(installationIdentifier, forHTTPHeaderField: "X-Install-Id")

        var allFields = fields
        allFields["requestId"] = requestID.uuidString
        allFields["schemaVersion"] = schemaVersion
        request.httpBody = MultipartFormData.makeBody(
            boundary: boundary,
            fields: allFields,
            imageData: imageData
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
        imageData: Data
    ) -> Data {
        var body = Data()

        for key in fields.keys.sorted() {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendUTF8("\(fields[key] ?? "")\r\n")
        }

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }
}

private nonisolated extension Data {
    mutating func appendUTF8(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
