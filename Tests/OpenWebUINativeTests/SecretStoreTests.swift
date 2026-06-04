import Foundation
import XCTest
@testable import OpenWebUINative

final class SecretStoreTests: XCTestCase {
    func testInMemorySecretStoreSavesUpdatesAndDeletesSecrets() async throws {
        let store = InMemorySecretStore()
        let id = "secret-\(UUID().uuidString)"

        try await store.saveSecret("first", id: id)
        let firstValue = try await store.readSecret(id: id)
        XCTAssertEqual(firstValue, "first")

        try await store.saveSecret("second", id: id)
        let secondValue = try await store.readSecret(id: id)
        XCTAssertEqual(secondValue, "second")

        try await store.deleteSecret(id: id)
        let deletedValue = try await store.readSecret(id: id)
        XCTAssertNil(deletedValue)
    }

    func testKeychainSecretStoreSavesUpdatesAndDeletesSecrets() async throws {
        let service = "dev.xtrasalty.OpenWebUINative.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        let id = "secret-\(UUID().uuidString)"

        try await store.saveSecret("first", id: id)
        let firstValue = try await store.readSecret(id: id)
        XCTAssertEqual(firstValue, "first")

        try await store.saveSecret("second", id: id)
        let secondValue = try await store.readSecret(id: id)
        XCTAssertEqual(secondValue, "second")

        try await store.deleteSecret(id: id)
        let deletedValue = try await store.readSecret(id: id)
        XCTAssertNil(deletedValue)
    }
}
