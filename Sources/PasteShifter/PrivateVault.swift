import AppKit
import CryptoKit
import LocalAuthentication
import Security
#if canImport(ClipboardCore)
import ClipboardCore
#endif

/// Encrypted, per-user private history. Touch ID gates each locked session;
/// the decrypted key is cached only until that session locks.
final class PrivateVault {
    private let service = "cl.pasteshifter.app.private-vault"
    private let account = NSUserName()
    private var unlockedKey: SymmetricKey?
    private var authenticationContext: LAContext?
    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Paste Shifter", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return directory.appendingPathComponent("PrivateHistory.enc")
    }

    func unlock(_ completion: @escaping (Result<History, Error>) -> Void) {
        // A second picker opening may ask the store to refresh its view while
        // the vault key is already live. Reuse it for the current session;
        // lock() clears this cache when the configured timeout expires.
        if let unlockedKey {
            do { completion(.success(try readHistory(key: unlockedKey))) }
            catch { completion(.failure(error)) }
            return
        }
        let context = LAContext()
        authenticationContext = context
        context.localizedReason = "Desbloquear el historial privado de Paste Shifter"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(.failure(error ?? VaultError.authenticationUnavailable)); return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Desbloquear el historial privado de Paste Shifter") { success, authError in
            DispatchQueue.main.async {
                guard self.authenticationContext === context else {
                    completion(.failure(VaultError.cancelled)); return
                }
                guard success else { completion(.failure(authError ?? VaultError.cancelled)); return }
                do {
                    let key = try self.key(context: context)
                    self.unlockedKey = key
                    completion(.success(try self.readHistory(key: key)))
                }
                catch { completion(.failure(error)) }
            }
        }
    }

    func save(_ history: History) throws {
        let data = try JSONEncoder().encode(history)
        guard let key = unlockedKey else { throw VaultError.locked }
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw VaultError.encryption }
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func erase() throws {
        unlockedKey = nil
        try? FileManager.default.removeItem(at: fileURL)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.keychain(status) }
    }

    func lock() {
        unlockedKey = nil
        authenticationContext?.invalidate()
        authenticationContext = nil
    }

    private func readHistory(key: SymmetricKey) throws -> History {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return History() }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: fileURL))
        return try JSONDecoder().decode(History.self, from: AES.GCM.open(sealed, using: key))
    }

    private func key(context: LAContext) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw VaultError.keychain(status) }
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessControl as String: try accessControl()]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw VaultError.keychain(addStatus) }
        return SymmetricKey(data: data)
    }

    private func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
            throw error?.takeRetainedValue() ?? VaultError.encryption as CFError
        }
        return control
    }

    enum VaultError: LocalizedError {
        case authenticationUnavailable, cancelled, encryption, locked, keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .authenticationUnavailable: return "Touch ID o la autenticación del Mac no están disponibles."
            case .cancelled: return "No se desbloqueó el historial privado."
            case .encryption: return "No se pudo cifrar el historial privado."
            case .locked: return "Desbloquea el historial privado antes de guardarlo."
            case .keychain(let status): return "El llavero de macOS devolvió el error \(status)."
            }
        }
    }
}
