import Crypto
import Foundation

struct OrbitalClientHello: Codable {
    static let messageType = "hello"
    let version = 1
    let messageType = Self.messageType
    let deviceID: UUID
    let deviceName: String
    let signingPublicKeyX963: Data
    let clientNonce: Data
    let pairingID: UUID?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, messageType, deviceID, deviceName, signingPublicKeyX963, clientNonce, pairingID
    }
    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    init(deviceID: UUID, deviceName: String, signingPublicKeyX963: Data, clientNonce: Data, pairingID: UUID?) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.signingPublicKeyX963 = signingPublicKeyX963
        self.clientNonce = clientNonce
        self.pairingID = pairingID
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard fields.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Orbital hello fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        let type = try values.decode(String.self, forKey: .messageType)
        guard version == 1, type == Self.messageType else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported Orbital hello version or type."))
        }
        deviceID = try values.decode(UUID.self, forKey: .deviceID)
        deviceName = try values.decode(String.self, forKey: .deviceName)
        signingPublicKeyX963 = try values.decode(Data.self, forKey: .signingPublicKeyX963)
        clientNonce = try values.decode(Data.self, forKey: .clientNonce)
        pairingID = try values.decodeIfPresent(UUID.self, forKey: .pairingID)
    }

    var isValid: Bool {
        deviceName.unicodeScalars.count <= 64 && !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        deviceName.utf8.count <= 256 && signingPublicKeyX963.count == 65 && signingPublicKeyX963.first == 0x04 &&
        clientNonce.count == 32
    }
}

struct OrbitalServerChallenge: Encodable {
    let version = 1
    let messageType = "challenge"
    let localDeviceID: UUID
    let serverNonce: Data

    init(localDeviceID: UUID, serverNonce: Data) {
        self.localDeviceID = localDeviceID
        self.serverNonce = serverNonce
    }
}

struct OrbitalPairProof: Decodable {
    let version = 1
    let messageType = "pair-proof"
    let pairingID: UUID
    let proofHMACSHA256: Data

    init(pairingID: UUID, proofHMACSHA256: Data) {
        self.pairingID = pairingID
        self.proofHMACSHA256 = proofHMACSHA256
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, messageType, pairingID, proofHMACSHA256
    }
    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard fields.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Orbital pair-proof fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1,
              try values.decode(String.self, forKey: .messageType) == "pair-proof" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported Orbital pair-proof version or type."))
        }
        pairingID = try values.decode(UUID.self, forKey: .pairingID)
        proofHMACSHA256 = try values.decode(Data.self, forKey: .proofHMACSHA256)
        guard proofHMACSHA256.count == 32 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Malformed Orbital pair-proof."))
        }
    }
}

struct OrbitalDeviceProof: Decodable {
    let version = 1
    let messageType = "device-proof"
    let signatureDER: Data

    init(signatureDER: Data) { self.signatureDER = signatureDER }

    private enum CodingKeys: String, CodingKey, CaseIterable { case version, messageType, signatureDER }
    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard fields.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Orbital device-proof fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1,
              try values.decode(String.self, forKey: .messageType) == "device-proof" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported Orbital device-proof version or type."))
        }
        signatureDER = try values.decode(Data.self, forKey: .signatureDER)
        guard (8...80).contains(signatureDER.count) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Malformed Orbital device-proof."))
        }
    }
}

struct OrbitalApprovalNotice: Encodable {
    let version = 1
    let messageType = "approval-needed"
    let comparisonCode: String

    init(comparisonCode: String) { self.comparisonCode = comparisonCode }
}

struct OrbitalHandshakeReply: Encodable {
    let version = 1
    let messageType: String
    let deviceID: UUID

    init(accepted deviceID: UUID) { messageType = "accepted"; self.deviceID = deviceID }
    init(rejected deviceID: UUID) { messageType = "rejected"; self.deviceID = deviceID }
}

struct OrbitalUnpairMessage: Codable {
    let version = 1
    let messageType = "unpair"
    let deviceID: UUID
    init(deviceID: UUID) { self.deviceID = deviceID }
    private enum CodingKeys: String, CodingKey, CaseIterable { case version, messageType, deviceID }
    private struct AnyCodingKey: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyCodingKey.self)
        guard fields.allKeys.allSatisfy({ CodingKeys.allCases.map(\.rawValue).contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Orbital unlink fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1,
              try values.decode(String.self, forKey: .messageType) == "unpair" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Orbital unlink message."))
        }
        deviceID = try values.decode(UUID.self, forKey: .deviceID)
    }
}

struct OrbitalUnpairAck: Codable {
    let version = 1
    let messageType = "unpair-ack"
    let deviceID: UUID
    init(deviceID: UUID) { self.deviceID = deviceID }
    private enum CodingKeys: String, CodingKey, CaseIterable { case version, messageType, deviceID }
    private struct AnyCodingKey: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyCodingKey.self)
        guard fields.allKeys.allSatisfy({ CodingKeys.allCases.map(\.rawValue).contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown Orbital unlink acknowledgement fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1,
              try values.decode(String.self, forKey: .messageType) == "unpair-ack" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Orbital unlink acknowledgement."))
        }
        deviceID = try values.decode(UUID.self, forKey: .deviceID)
    }
}

/// Canonical transcript construction and cryptographic verification shared by
/// the Mac implementation and Android's Kotlin port. See OrbitalProtocol/README.md.
enum OrbitalHandshake {
    static func pairProof(secret: Data, pairingID: UUID, localDeviceID: UUID,
                          hello: OrbitalClientHello, serverNonce: Data) throws -> Data {
        guard secret.count == 32, hello.isValid, serverNonce.count == 32 else { throw HandshakeError.invalidInput }
        let transcript = try pairingTranscript(pairingID: pairingID, localDeviceID: localDeviceID,
                                               hello: hello, serverNonce: serverNonce)
        let key = SymmetricKey(data: secret)
        return Data(HMAC<SHA256>.authenticationCode(for: transcript, using: key))
    }

    static func verifyPairProof(_ proof: Data, secret: Data, pairingID: UUID, localDeviceID: UUID,
                                hello: OrbitalClientHello, serverNonce: Data) -> Bool {
        guard proof.count == 32, secret.count == 32, hello.isValid, serverNonce.count == 32,
              let transcript = try? pairingTranscript(pairingID: pairingID, localDeviceID: localDeviceID,
                                                      hello: hello, serverNonce: serverNonce) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: transcript, using: SymmetricKey(data: secret))
    }

    static func comparisonCode(secret: Data, pairingID: UUID, localDeviceID: UUID,
                               hello: OrbitalClientHello, serverNonce: Data) throws -> String {
        guard secret.count == 32 else { throw HandshakeError.invalidInput }
        var message = Data("PasteShifter/Orbital/SAS/v1\0".utf8)
        message.append(try pairingTranscript(pairingID: pairingID, localDeviceID: localDeviceID,
                                             hello: hello, serverNonce: serverNonce))
        let digest = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
        let prefix = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", prefix % 1_000_000)
    }

    static func signatureInput(localDeviceID: UUID, hello: OrbitalClientHello, serverNonce: Data) throws -> Data {
        guard hello.isValid, serverNonce.count == 32 else { throw HandshakeError.invalidInput }
        var transcript = Data("PasteShifter/Orbital/Auth/v1\0".utf8)
        transcript.append(uuidBytes(localDeviceID))
        transcript.append(uuidBytes(hello.deviceID))
        transcript.append(hello.clientNonce)
        transcript.append(serverNonce)
        transcript.append(hello.signingPublicKeyX963)
        try appendName(hello.deviceName, to: &transcript)
        return transcript
    }

    static func verifyDeviceSignature(_ signatureDER: Data, localDeviceID: UUID,
                                      hello: OrbitalClientHello, serverNonce: Data,
                                      trustedPublicKey: Data) -> Bool {
        guard signatureDER.count >= 8, signatureDER.count <= 80,
              trustedPublicKey == hello.signingPublicKeyX963,
              let input = try? signatureInput(localDeviceID: localDeviceID, hello: hello, serverNonce: serverNonce),
              let key = try? P256.Signing.PublicKey(x963Representation: trustedPublicKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureDER) else { return false }
        return key.isValidSignature(signature, for: input)
    }

    private static func pairingTranscript(pairingID: UUID, localDeviceID: UUID,
                                          hello: OrbitalClientHello, serverNonce: Data) throws -> Data {
        guard hello.isValid, serverNonce.count == 32 else { throw HandshakeError.invalidInput }
        var transcript = Data("PasteShifter/Orbital/Pair/v1\0".utf8)
        transcript.append(uuidBytes(pairingID))
        transcript.append(uuidBytes(localDeviceID))
        transcript.append(uuidBytes(hello.deviceID))
        transcript.append(hello.clientNonce)
        transcript.append(serverNonce)
        transcript.append(hello.signingPublicKeyX963)
        try appendName(hello.deviceName, to: &transcript)
        return transcript
    }

    private static func appendName(_ name: String, to data: inout Data) throws {
        let bytes = Data(name.utf8)
        guard !bytes.isEmpty, bytes.count <= 256, bytes.count <= Int(UInt16.max) else { throw HandshakeError.invalidInput }
        var length = UInt16(bytes.count).bigEndian
        data.append(withUnsafeBytes(of: &length) { Data($0) })
        data.append(bytes)
    }

    private static func uuidBytes(_ id: UUID) -> Data {
        var value = id.uuid
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    enum HandshakeError: Error { case invalidInput }
}
