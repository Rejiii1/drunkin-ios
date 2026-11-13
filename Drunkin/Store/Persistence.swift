import CryptoKit
import Foundation
import Security

/// One JSON file per tasting in Application Support, written atomically and
/// encrypted at rest by iOS Data Protection. Nothing leaves the phone except
/// what the user sends to their table or shares as a file.
struct TastingStore {
    let directory: URL

    static func live() -> TastingStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return TastingStore(directory: base.appendingPathComponent("Tastings", isDirectory: true))
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    func loadAll() -> [Tasting] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(Tasting.self, from: data)
        }
    }

    func save(_ t: Tasting) throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(t)
        try data.write(to: url(t.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Rejoin tokens live in the Keychain, this device only, never in backups.
enum Keychain {
    private static let service = "fun.dunkin.drunkin.rejoin"

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    static func removeAll() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }
}

enum Secrets {
    static func token() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "No secure randomness available")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func joinCode() -> String {
        var rng = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0..<1_000_000, using: &rng))
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Compares two secrets without leaking how many leading characters match.
    static func equal(_ a: String, _ b: String) -> Bool {
        let x = Array(sha256(a).utf8), y = Array(sha256(b).utf8)
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
