import Crypto
import Foundation
import Security

/// Creates and persists the Mac's self-signed TLS identity. The private key is
/// generated and used by Keychain; it is never exported from the key store.
struct OrbitalLocalIdentity {
    let secIdentity: SecIdentity
    let certificateDER: Data
    let certificateSHA256: Data

    // v2 intentionally rotates away from early development keys, whose
    // default Keychain ACL could leave signing blocked after authorization
    // was denied or the app was re-signed.
    private static let keyTag = Data("cl.pasteshifter.orbital.tls-key.v2".utf8)
    private static let certificateLabel = "Paste Shifter Orbital TLS v2"

    static func loadOrCreate() throws -> OrbitalLocalIdentity {
        let key = try loadOrCreatePrivateKey()
        if let certificate = try loadCertificate(), let identity = identity(for: certificate) {
            let der = SecCertificateCopyData(certificate) as Data
            return OrbitalLocalIdentity(secIdentity: identity, certificateDER: der,
                                        certificateSHA256: Data(SHA256.hash(data: der)))
        }

        guard let publicKey = SecKeyCopyPublicKey(key) else { throw IdentityError.publicKeyUnavailable }
        var publicKeyError: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &publicKeyError) as Data? else {
            throw publicKeyError?.takeRetainedValue() ?? IdentityError.publicKeyUnavailable
        }
        let certificateDER = try makeCertificate(publicKey: publicKeyData, signingKey: key)
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw IdentityError.certificateCreationFailed
        }
        try saveCertificate(certificate)
        guard let identity = identity(for: certificate) else { throw IdentityError.keychainIdentityNotFound }
        return OrbitalLocalIdentity(secIdentity: identity, certificateDER: certificateDER,
                                    certificateSHA256: Data(SHA256.hash(data: certificateDER)))
    }

    private static func loadOrCreatePrivateKey() throws -> SecKey {
        let query: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate, kSecAttrApplicationTag: keyTag, kSecReturnRef: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let item, CFGetTypeID(item) == SecKeyGetTypeID() {
            return unsafeBitCast(item, to: SecKey.self)
        }
        guard status == errSecItemNotFound else { throw IdentityError.keychain(status) }
        var access: SecAccess?
        let accessStatus = SecAccessCreate(certificateLabel as CFString, nil, &access)
        guard accessStatus == errSecSuccess, let access else { throw IdentityError.keychain(accessStatus) }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrLabel: certificateLabel, kSecAttrApplicationTag: keyTag, kSecAttrIsPermanent: true,
            kSecAttrAccess: access]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? IdentityError.keyGenerationFailed
        }
        return key
    }

    private static func loadCertificate() throws -> SecCertificate? {
        let query: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecAttrLabel: certificateLabel, kSecReturnRef: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item, CFGetTypeID(item) == SecCertificateGetTypeID() else {
            throw IdentityError.keychain(status)
        }
        return unsafeBitCast(item, to: SecCertificate.self)
    }

    private static func saveCertificate(_ certificate: SecCertificate) throws {
        let item: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: certificate,
                                     kSecAttrLabel: certificateLabel]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw IdentityError.keychain(status) }
    }

    private static func identity(for certificate: SecCertificate) -> SecIdentity? {
        var result: SecIdentity?
        guard SecIdentityCreateWithCertificate(nil, certificate, &result) == errSecSuccess else { return nil }
        return result
    }

    /// Builds the small self-signed X.509 certificate directly in DER so the
    /// private key can sign inside Keychain without exporting its bytes.
    private static func makeCertificate(publicKey: Data, signingKey: SecKey) throws -> Data {
        let signatureAlgorithm = sequence(oid("1.2.840.10045.4.3.2")) // ecdsa-with-SHA256
        let name = sequence(set(sequence(oid("2.5.4.3") + utf8("Paste Shifter Orbital"))))
        var serial = [UInt8](Data((0..<16).map { _ in UInt8.random(in: 0...255) }))
        serial[0] &= 0x7f
        if serial.allSatisfy({ $0 == 0 }) { serial[serial.count - 1] = 1 }
        let validity = sequence(utcTime(Date().addingTimeInterval(-300)) + utcTime(Date().addingTimeInterval(60 * 60 * 24 * 365 * 10)))
        let subjectPublicKeyInfo = sequence(sequence(oid("1.2.840.10045.2.1") + oid("1.2.840.10045.3.1.7")) + bitString(publicKey))
        let extensions = sequence(
            extensionDER("2.5.29.19", critical: true, value: sequence()) +
            extensionDER("2.5.29.15", critical: true, value: bitString(Data([0x80]), unusedBits: 7)) +
            extensionDER("2.5.29.37", value: sequence(oid("1.3.6.1.5.5.7.3.1"))) +
            extensionDER("2.5.29.17", value: sequence(tlv(0x82, Data("orbital.pasteshifter.local".utf8))))
        )
        let tbs = sequence(tlv(0xa0, integer(Data([2]))) + integer(Data(serial)) + signatureAlgorithm + name + validity + name + subjectPublicKeyInfo + tlv(0xa3, extensions))
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(signingKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error) as Data? else {
            throw error?.takeRetainedValue() ?? IdentityError.signatureFailed
        }
        return sequence(tbs + signatureAlgorithm + bitString(signature))
    }

    private static func extensionDER(_ identifier: String, critical: Bool = false, value: Data) -> Data {
        sequence(oid(identifier) + (critical ? tlv(0x01, Data([0xff])) : Data()) + tlv(0x04, value))
    }
    private static func sequence(_ contents: Data = Data()) -> Data { tlv(0x30, contents) }
    private static func set(_ contents: Data) -> Data { tlv(0x31, contents) }
    private static func utf8(_ value: String) -> Data { tlv(0x0c, Data(value.utf8)) }
    private static func integer(_ bytes: Data) -> Data {
        var value = bytes
        while value.count > 1 && value.first == 0 { value.removeFirst() }
        if let first = value.first, first & 0x80 != 0 { value.insert(0, at: 0) }
        return tlv(0x02, value)
    }
    private static func bitString(_ bytes: Data, unusedBits: UInt8 = 0) -> Data {
        tlv(0x03, Data([unusedBits]) + bytes)
    }
    private static func oid(_ value: String) -> Data {
        let parts = value.split(separator: ".").compactMap { UInt64($0) }
        guard parts.count >= 2 else { return Data() }
        var encoded: [UInt8] = []
        for component in [parts[0] * 40 + parts[1]] + parts.dropFirst(2) {
            var n = component
            var bytes = [UInt8(n & 0x7f)]
            n >>= 7
            while n > 0 { bytes.insert(UInt8(n & 0x7f) | 0x80, at: 0); n >>= 7 }
            encoded.append(contentsOf: bytes)
        }
        return tlv(0x06, Data(encoded))
    }
    private static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(formatter.string(from: date).utf8))
    }
    private static func tlv(_ tag: UInt8, _ value: Data) -> Data {
        var result = Data([tag])
        let count = value.count
        if count < 128 { result.append(UInt8(count)) }
        else {
            var bytes: [UInt8] = []
            var length = count
            while length > 0 { bytes.insert(UInt8(length & 0xff), at: 0); length >>= 8 }
            result.append(0x80 | UInt8(bytes.count)); result.append(contentsOf: bytes)
        }
        result.append(value)
        return result
    }

    private enum IdentityError: Error {
        case keyGenerationFailed, publicKeyUnavailable, certificateCreationFailed
        case signatureFailed, keychainIdentityNotFound, keychain(OSStatus)
    }
}
