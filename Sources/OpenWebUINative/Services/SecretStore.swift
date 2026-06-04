import Foundation
import Security

protocol SecretStoring: Sendable {
    func readSecret(id: String) async throws -> String?
    func saveSecret(_ secret: String, id: String) async throws
    func deleteSecret(id: String) async throws
}

enum SecretStoreError: Error, LocalizedError, Equatable {
    case unhandledStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain returned status \(status)."
        case .invalidData:
            return "The stored secret could not be decoded."
        }
    }
}

actor InMemorySecretStore: SecretStoring {
    private var secrets: [String: String]

    init(_ secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    func readSecret(id: String) async throws -> String? {
        secrets[id]
    }

    func saveSecret(_ secret: String, id: String) async throws {
        secrets[id] = secret
    }

    func deleteSecret(id: String) async throws {
        secrets[id] = nil
    }
}

struct KeychainSecretStore: SecretStoring {
    private let service: String

    init(service: String = "dev.xtrasalty.OpenWebUINative.providers") {
        self.service = service
    }

    func readSecret(id: String) async throws -> String? {
        var query = baseQuery(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return secret
    }

    func saveSecret(_ secret: String, id: String) async throws {
        let data = Data(secret.utf8)
        var query = baseQuery(id: id)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.unhandledStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(addStatus)
        }
    }

    func deleteSecret(id: String) async throws {
        let status = SecItemDelete(baseQuery(id: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
    }
}
