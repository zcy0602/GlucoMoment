//
//  FoodAnalysisCredentialStore.swift
//  GlucoMoment
//

import Foundation
import Security

/// 每个服务商单独保存一个 Key，切换服务商不需要重新填写
nonisolated protocol FoodAnalysisCredentialStoring: Sendable {
    func apiKey(for provider: FoodAnalysisAPIProvider) async throws -> String?
    func save(apiKey: String, for provider: FoodAnalysisAPIProvider) async throws
    func deleteAPIKey(for provider: FoodAnalysisAPIProvider) async throws
}

nonisolated enum FoodAnalysisAPIKeyValidator {
    /// 各家 Key 格式不同（sk-、AIza、带点号等），只做基本校验
    static func normalized(_ apiKey: String) throws -> String {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 8,
              !normalized.contains(where: \.isWhitespace) else {
            throw CredentialStoreError.invalidKey
        }
        return normalized
    }
}

nonisolated enum CredentialStoreError: LocalizedError, Sendable {
    case invalidKey
    case unexpectedData
    case securityStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            "请输入有效的 API Key。"
        case .unexpectedData:
            "钥匙串中的 API Key 无法读取。"
        case .securityStatus(let status):
            "钥匙串操作失败（\(status)）。"
        }
    }
}

actor KeychainFoodAnalysisCredentialStore: FoodAnalysisCredentialStoring {
    private let service: String

    init(service: String = "com.zcy0602.GlucoMoment.food-analysis") {
        self.service = service
    }

    func apiKey(for provider: FoodAnalysisAPIProvider) throws -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.securityStatus(status) }
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.unexpectedData
        }
        return key
    }

    func save(apiKey: String, for provider: FoodAnalysisAPIProvider) throws {
        let normalized = try FoodAnalysisAPIKeyValidator.normalized(apiKey)
        guard let data = normalized.data(using: .utf8) else {
            throw CredentialStoreError.invalidKey
        }
        let baseQuery = baseQuery(for: provider)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.securityStatus(updateStatus)
        }

        var item = baseQuery
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.securityStatus(addStatus)
        }
    }

    func deleteAPIKey(for provider: FoodAnalysisAPIProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.securityStatus(status)
        }
    }

    /// 百炼沿用旧版账户名，升级后已保存的 Key 继续可用
    private static func account(for provider: FoodAnalysisAPIProvider) -> String {
        provider == .dashScope ? "QwenModelStudioAPIKey" : "FoodAnalysisAPIKey.\(provider.rawValue)"
    }

    private func baseQuery(for provider: FoodAnalysisAPIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account(for: provider),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

actor InMemoryFoodAnalysisCredentialStore: FoodAnalysisCredentialStoring {
    private var storedKeys: [FoodAnalysisAPIProvider: String]

    init(apiKeys: [FoodAnalysisAPIProvider: String] = [:]) {
        storedKeys = apiKeys
    }

    func apiKey(for provider: FoodAnalysisAPIProvider) -> String? { storedKeys[provider] }

    func save(apiKey: String, for provider: FoodAnalysisAPIProvider) throws {
        storedKeys[provider] = try FoodAnalysisAPIKeyValidator.normalized(apiKey)
    }

    func deleteAPIKey(for provider: FoodAnalysisAPIProvider) {
        storedKeys[provider] = nil
    }
}
