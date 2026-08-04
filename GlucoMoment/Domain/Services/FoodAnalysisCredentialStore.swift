//
//  FoodAnalysisCredentialStore.swift
//  GlucoMoment
//

import Foundation
import Security

nonisolated protocol FoodAnalysisCredentialStoring: Sendable {
    func apiKey() async throws -> String?
    func save(apiKey: String) async throws
    func deleteAPIKey() async throws
}

nonisolated enum CredentialStoreError: LocalizedError, Sendable {
    case invalidKey
    case unexpectedData
    case securityStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            "请输入有效的阿里云百炼 API Key。"
        case .unexpectedData:
            "钥匙串中的 API Key 无法读取。"
        case .securityStatus(let status):
            "钥匙串操作失败（\(status)）。"
        }
    }
}

actor KeychainFoodAnalysisCredentialStore: FoodAnalysisCredentialStoring {
    private let service: String
    private let account = "QwenModelStudioAPIKey"

    init(service: String = "com.zcy0602.GlucoMoment.food-analysis") {
        self.service = service
    }

    func apiKey() throws -> String? {
        var query = baseQuery
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

    func save(apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("sk-"), normalized.count >= 20,
              let data = normalized.data(using: .utf8) else {
            throw CredentialStoreError.invalidKey
        }

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

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.securityStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

actor InMemoryFoodAnalysisCredentialStore: FoodAnalysisCredentialStoring {
    private var storedKey: String?

    init(apiKey: String? = nil) {
        storedKey = apiKey
    }

    func apiKey() -> String? { storedKey }

    func save(apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("sk-"), normalized.count >= 20 else {
            throw CredentialStoreError.invalidKey
        }
        storedKey = normalized
    }

    func deleteAPIKey() {
        storedKey = nil
    }
}
