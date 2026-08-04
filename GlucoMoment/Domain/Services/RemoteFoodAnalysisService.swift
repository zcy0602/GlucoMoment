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
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        let requestID = UUID()
        var lastError: (any Error)?

        for attempt in 0...maximumRetryCount {
            do {
                return try await performRequest(
                    requestID: requestID,
                    imageData: imageData,
                    userFoodContext: userFoodContext,
                    mealPeriod: mealPeriod
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
        requestID: UUID,
        imageData: Data,
        userFoodContext: String?,
        mealPeriod: MealPeriod?
    ) async throws -> FoodRecognitionResult {
        let boundary = "GlucoMoment-\(requestID.uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-Id")
        request.setValue(installationIdentifier, forHTTPHeaderField: "X-Install-Id")
        request.httpBody = MultipartFormData.makeBody(
            boundary: boundary,
            fields: [
                "requestId": requestID.uuidString,
                "schemaVersion": "1",
                "locale": "zh-CN",
                "mealPeriod": mealPeriod?.rawValue ?? "",
                "userFoodContext": userFoodContext ?? ""
            ],
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

        do {
            return try JSONDecoder().decode(FoodAnalysisProxyResponseDTO.self, from: data).makeResult()
        } catch {
            throw FoodAnalysisError.invalidResponse
        }
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
