import Combine
import Foundation
import AppKit
import UserNotifications

/// Shared, versioned message shapes for the native Mac app and Android
/// client. Transport and pairing must be authenticated before these
/// values are accepted from the network.
struct OrbitalClipEnvelope: Codable, Equatable {
    static let currentVersion = 1
    static let maximumUTF8Bytes = 256_000

    let version: Int
    let clipID: UUID
    let originDeviceID: UUID
    let originDeviceName: String
    let text: String
    /// Unix epoch time in milliseconds, matching Android's System.currentTimeMillis().
    let createdAtMilliseconds: Int64

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, clipID, originDeviceID, originDeviceName, text, createdAtMilliseconds
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    init(clipID: UUID = UUID(), originDeviceID: UUID, originDeviceName: String, text: String, createdAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) {
        self.version = Self.currentVersion
        self.clipID = clipID
        self.originDeviceID = originDeviceID
        self.originDeviceName = String(String.UnicodeScalarView(originDeviceName.unicodeScalars.prefix(64)))
        self.text = text
        self.createdAtMilliseconds = createdAtMilliseconds
    }

    init(from decoder: Decoder) throws {
        let allFields = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedFields = Set(CodingKeys.allCases.map(\.rawValue))
        guard allFields.allKeys.allSatisfy({ allowedFields.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                     debugDescription: "Orbital v1 envelope contains unsupported fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        clipID = try values.decode(UUID.self, forKey: .clipID)
        originDeviceID = try values.decode(UUID.self, forKey: .originDeviceID)
        originDeviceName = try values.decode(String.self, forKey: .originDeviceName)
        text = try values.decode(String.self, forKey: .text)
        createdAtMilliseconds = try values.decode(Int64.self, forKey: .createdAtMilliseconds)
    }

    var isValid: Bool {
        version == Self.currentVersion &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        text.utf8.count <= Self.maximumUTF8Bytes &&
        !originDeviceName.isEmpty &&
        originDeviceName.unicodeScalars.count <= 64 &&
        createdAtMilliseconds >= 0
    }
}

/// Length-prefixed wire framing shared with the Android client. The caller
/// must read exactly one frame; no untrusted length is used for allocation
/// until it has passed this upper bound.
enum OrbitalWireCodec {
    // JSON may expand control characters to six-byte \uXXXX escapes.
    static let maximumJSONBytes = 1_600_000
    private static let headerBytes = 4

    static func encode<Message: Encodable>(_ message: Message) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(message)
        guard body.count <= maximumJSONBytes else { throw WireError.frameTooLarge }
        var length = UInt32(body.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(body)
        return frame
    }

    static func decode<Message: Decodable>(_ type: Message.Type, frame: Data) throws -> Message {
        guard frame.count >= headerBytes else { throw WireError.malformedFrame }
        let length = frame.prefix(headerBytes).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maximumJSONBytes,
              frame.count == headerBytes + Int(length) else { throw WireError.malformedFrame }
        let body = Data(frame.dropFirst(headerBytes))
        return try JSONDecoder().decode(type, from: body)
    }

    static func decodeClip(_ frame: Data) throws -> OrbitalClipEnvelope {
        let envelope = try decode(OrbitalClipEnvelope.self, frame: frame)
        guard envelope.isValid else { throw WireError.invalidEnvelope }
        return envelope
    }

    enum WireError: Error {
        case frameTooLarge, malformedFrame, invalidEnvelope
    }
}

struct OrbitalPairedDevice: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Uncompressed P-256 public key used to verify fresh client challenges.
    /// This is public material; private keys and pairing secrets never enter this model.
    var signingPublicKeyX963: Data
    var pairedAt: Date
}

/// Short-lived QR content. It contains no address: Android must discover the
/// matching service on the LAN, and the certificate fingerprint pins TLS.
/// The secret is never published through Bonjour and this value is never saved.
struct OrbitalPairingPayload: Codable, Equatable {
    static let currentVersion = 1
    static let lifetimeMilliseconds: Int64 = 120_000

    let version: Int
    let pairingID: UUID
    let localDeviceID: UUID
    let certificateFingerprintSHA256: String
    let pairingSecret: Data
    let expiresAtMilliseconds: Int64

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, pairingID, localDeviceID, certificateFingerprintSHA256, pairingSecret, expiresAtMilliseconds
    }
    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    init(localDeviceID: UUID, certificateFingerprintSHA256: Data, now: Date = Date()) throws {
        guard certificateFingerprintSHA256.count == 32 else { throw PayloadError.invalidFingerprint }
        version = Self.currentVersion
        pairingID = UUID()
        self.localDeviceID = localDeviceID
        self.certificateFingerprintSHA256 = certificateFingerprintSHA256.map { String(format: "%02x", $0) }.joined()
        var generator = SystemRandomNumberGenerator()
        pairingSecret = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        expiresAtMilliseconds = Int64(now.timeIntervalSince1970 * 1_000) + Self.lifetimeMilliseconds
    }

    init(from decoder: Decoder) throws {
        let allFields = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedFields = Set(CodingKeys.allCases.map(\.rawValue))
        guard allFields.allKeys.allSatisfy({ allowedFields.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                     debugDescription: "Orbital pairing v1 contains unsupported fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        pairingID = try values.decode(UUID.self, forKey: .pairingID)
        localDeviceID = try values.decode(UUID.self, forKey: .localDeviceID)
        certificateFingerprintSHA256 = try values.decode(String.self, forKey: .certificateFingerprintSHA256)
        pairingSecret = try values.decode(Data.self, forKey: .pairingSecret)
        expiresAtMilliseconds = try values.decode(Int64.self, forKey: .expiresAtMilliseconds)
    }

    func isValid(now: Date = Date()) -> Bool {
        let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1_000)
        let fingerprintIsHex = certificateFingerprintSHA256.utf8.count == 64 &&
            certificateFingerprintSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        return version == Self.currentVersion && pairingSecret.count == 32 && fingerprintIsHex &&
            expiresAtMilliseconds > nowMilliseconds &&
            expiresAtMilliseconds <= nowMilliseconds + Self.lifetimeMilliseconds + 1_000
    }

    func encodedForQR() throws -> Data {
        guard isValid() else { throw PayloadError.invalidPayload }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    private enum PayloadError: Error { case invalidFingerprint, invalidPayload }
}

/// UI-facing model. Network.framework callbacks must hop to the main
/// queue before calling mutating methods, matching ClipboardStore's UI usage.
final class OrbitalCoordinator: ObservableObject {
    enum Availability: Equatable {
        case preparation
        case ready
    }

    @Published private(set) var pairedDevices: [OrbitalPairedDevice] = []
    var connectedPairedDevices: [OrbitalPairedDevice] {
        pairedDevices.filter { connectedDeviceIDs.contains($0.id) }
    }
    @Published private(set) var lastReceivedDeviceName: String?
    @Published private(set) var availability: Availability = .preparation
    @Published private(set) var connectionStatus = "Sin conexión activa"
    @Published private(set) var pairingQRData: Data?
    @Published private(set) var pairingExpiresAt: Date?
    @Published private(set) var isPreparingPairing = false
    @Published private(set) var pendingApproval: OrbitalPairingRequest?
    @Published var isPaused = UserDefaults.standard.bool(forKey: "orbital.isPaused") {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "orbital.isPaused")
            if isPaused {
                pairingExpiryTimer?.invalidate()
                pairingExpiryTimer = nil
                pairingQRData = nil
                pairingExpiresAt = nil
                pairingAttemptID = nil
                isPreparingPairing = false
                pendingApproval = nil
                pairingApprovalResolution = nil
                connectedDeviceIDs.removeAll()
                pendingManualSends.removeAll()
                updateAvailability()
                connectionStatus = "Orbital está pausado."
                transport?.stop()
            } else if !pairedDevices.isEmpty {
                connectionStatus = "Iniciando conexión local con dispositivos emparejados…"
                transport?.resumeForPairedDevices()
            }
        }
    }
    /// Automatic outbound sharing is opt-in. An explicit per-clip send action
    /// may be offered separately once the authenticated transport is available.
    @Published var automaticSharingEnabled = UserDefaults.standard.object(forKey: "orbital.automaticSharingEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(automaticSharingEnabled, forKey: "orbital.automaticSharingEnabled") }
    }
    @Published var receiveSoundEnabled = UserDefaults.standard.object(forKey: "orbital.receiveSoundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(receiveSoundEnabled, forKey: "orbital.receiveSoundEnabled") }
    }
    @Published var reconnectNotificationsEnabled = UserDefaults.standard.bool(forKey: "orbital.reconnectNotificationsEnabled") {
        didSet {
            UserDefaults.standard.set(reconnectNotificationsEnabled, forKey: "orbital.reconnectNotificationsEnabled")
            if reconnectNotificationsEnabled {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    private let storageKey = "orbital.pairedDevices.v1"
    private let localDeviceIDKey = "orbital.localDeviceID.v1"
    private var receivedClipIDs = Set<UUID>()
    private var receivedClipIDOrder: [UUID] = []
    private var connectedDeviceIDs = Set<UUID>()
    private var pendingManualSends: [UUID: [OrbitalClipEnvelope]] = [:]
    private var pairingApprovalResolution: ((Bool) -> Void)?
    private var pairingExpiryTimer: Timer?
    private var pairingAttemptID: UUID?
    private weak var clipboardStore: ClipboardStore?
    private var transport: OrbitalLocalTransport?
    private(set) lazy var localDeviceID: UUID = {
        if let raw = UserDefaults.standard.string(forKey: localDeviceIDKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: localDeviceIDKey)
        return id
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let devices = try? JSONDecoder().decode([OrbitalPairedDevice].self, from: data) {
            pairedDevices = devices
        }
    }

    func configure(store: ClipboardStore) {
        clipboardStore = store
        store.onNormalClipInserted = { [weak self] text in
            self?.sendAutomatically(text)
        }
        guard transport == nil else { return }
        let service = OrbitalLocalTransport(localDeviceID: localDeviceID) { [weak self] in
            guard let self else { return [] }
            if Thread.isMainThread { return self.pairedDevices }
            return DispatchQueue.main.sync { self.pairedDevices }
        }
        service.onState = { [weak self] state in self?.connectionStatus = state }
        service.onListenerReady = { [weak self] in self?.connectionStatus = "Esperando un dispositivo en esta red Wi‑Fi…" }
        service.onIncomingClip = { [weak self] envelope in
            guard let self, let store = self.clipboardStore else { return }
            _ = self.receive(envelope, into: store)
        }
        service.onUnpair = { [weak self] id in self?.removePairedDevice(id, disconnect: false) }
        service.onPairingRequest = { [weak self] request, resolve in
            guard let self else { resolve(false); return }
            self.pairingExpiryTimer?.invalidate()
            self.pairingExpiryTimer = nil
            self.pairingQRData = nil
            self.pairingExpiresAt = nil
            self.pendingApproval = request
            self.pairingApprovalResolution = resolve
            self.connectionStatus = "Compara el código con tu Android y aprueba el dispositivo."
        }
        service.onPairingCancelled = { [weak self] requestID in
            guard let self, self.pendingApproval?.id == requestID else { return }
            self.pendingApproval = nil
            self.pairingApprovalResolution = nil
            if !self.isPaused { self.connectionStatus = "El emparejamiento venció o se desconectó." }
        }
        service.onAuthenticated = { [weak self, weak service] id, name in
            guard let self else { return }
            if self.isPaused {
                service?.disconnectDevice(id)
                return
            }
            self.connectedDeviceIDs.insert(id)
            self.updateAvailability()
            self.connectionStatus = "Conectado de forma segura con \(name)."
            let queued = self.pendingManualSends.removeValue(forKey: id) ?? []
            for envelope in queued { service?.send(envelope, to: id) }
            if self.reconnectNotificationsEnabled {
                let content = UNMutableNotificationContent()
                content.title = "Paste Shifter · Orbital"
                content.body = "Conexión local restablecida con \(name)."
                let request = UNNotificationRequest(identifier: "orbital-reconnect-\(id)-\(UUID())", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
        service.onDisconnected = { [weak self] id in
            guard let self else { return }
            self.connectedDeviceIDs.remove(id)
            self.updateAvailability()
            if self.isPaused {
                self.connectionStatus = "Orbital está pausado."
            } else if self.connectedDeviceIDs.isEmpty {
                self.connectionStatus = "Sin dispositivos conectados"
            }
        }
        transport = service
        if !isPaused, !pairedDevices.isEmpty {
            connectionStatus = "Iniciando conexión local con dispositivos emparejados…"
            service.resumeForPairedDevices()
        }
    }

    func beginPairing() {
        if isPaused { isPaused = false }
        guard let transport else {
            connectionStatus = "Orbital todavía no está inicializado."
            return
        }
        // Keychain may ask macOS to unlock or authorize the local TLS key.
        // Keep this work off the UI thread so the button responds immediately
        // and the window does not appear frozen behind a system prompt.
        let attemptID = UUID()
        pairingAttemptID = attemptID
        isPreparingPairing = true
        pairingQRData = nil
        pairingExpiresAt = nil
        connectionStatus = "Preparando una conexión segura…"
        let deviceID = localDeviceID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let identity = try OrbitalLocalIdentity.loadOrCreate()
                let payload = try OrbitalPairingPayload(localDeviceID: deviceID,
                                                        certificateFingerprintSHA256: identity.certificateSHA256)
                let qrData = try payload.encodedForQR()
                DispatchQueue.main.async {
                    guard let self, self.pairingAttemptID == attemptID, !self.isPaused else { return }
                    self.isPreparingPairing = false
                    self.pairingQRData = qrData
                    self.pairingExpiresAt = Date(timeIntervalSince1970: TimeInterval(payload.expiresAtMilliseconds) / 1_000)
                    self.pairingExpiryTimer?.invalidate()
                    self.pairingExpiryTimer = Timer.scheduledTimer(
                        withTimeInterval: TimeInterval(OrbitalPairingPayload.lifetimeMilliseconds) / 1_000,
                        repeats: false
                    ) { [weak self] _ in self?.endPairing() }
                    self.connectionStatus = "Abriendo una conexión directa por Wi‑Fi…"
                    transport.start(pairing: payload, identity: identity)
                }
            } catch {
                let detail = String(reflecting: error)
                NSLog("Orbital pairing identity error: %@", detail)
                DispatchQueue.main.async {
                    guard let self, self.pairingAttemptID == attemptID else { return }
                    self.isPreparingPairing = false
                    self.pairingQRData = nil
                    self.pairingExpiresAt = nil
                    self.connectionStatus = "No se pudo preparar la conexión segura. Si macOS pregunta, permite el acceso de Paste Shifter en el Llavero."
                }
            }
        }
    }

    func endPairing() {
        pairingAttemptID = nil
        isPreparingPairing = false
        pairingExpiryTimer?.invalidate()
        pairingExpiryTimer = nil
        pairingQRData = nil
        pairingExpiresAt = nil
        transport?.stopPairing()
    }

    func transportShutdown() { transport?.stop() }

    func approvePairing() {
        guard let request = pendingApproval, let resolve = pairingApprovalResolution else { return }
        addPairedDevice(OrbitalPairedDevice(id: request.deviceID, name: request.deviceName,
                                            signingPublicKeyX963: request.signingPublicKeyX963, pairedAt: Date()))
        pendingApproval = nil
        pairingApprovalResolution = nil
        resolve(true)
    }

    func rejectPairing() {
        let resolve = pairingApprovalResolution
        pendingApproval = nil
        pairingApprovalResolution = nil
        resolve?(false)
        transport?.stopPairing()
    }

    func sendManually(_ text: String, from space: ClipboardSpace, to deviceID: UUID) {
        guard mayManuallyShare(space: space, text: text, to: deviceID) else { return }
        let envelope = OrbitalClipEnvelope(originDeviceID: localDeviceID,
                                           originDeviceName: Self.localDeviceName,
                                           text: text)
        if connectedDeviceIDs.contains(deviceID) {
            transport?.send(envelope, to: deviceID)
        } else {
            var queue = pendingManualSends[deviceID, default: []]
            if queue.count >= 20 { queue.removeFirst() }
            queue.append(envelope)
            pendingManualSends[deviceID] = queue
            connectionStatus = "Copia en espera; se enviará al reconectar con Android."
        }
    }

    private func sendAutomatically(_ text: String) {
        guard !isPaused, mayAutomaticallyShare(space: .normal, text: text) else { return }
        transport?.send(OrbitalClipEnvelope(originDeviceID: localDeviceID,
                                            originDeviceName: Self.localDeviceName,
                                            text: text))
    }

    /// Eligibility for the explicit per-clip action. The transport must still
    /// authenticate the peer before sending; excluded spaces can never be shared.
    func mayManuallyShare(space: ClipboardSpace, text: String) -> Bool {
        isEligible(space: space, text: text)
    }

    func mayManuallyShare(space: ClipboardSpace, text: String, to deviceID: UUID) -> Bool {
        isEligible(space: space, text: text) && pairedDevices.contains { $0.id == deviceID }
    }

    /// Automatic sharing is separately opt-in and defaults to off.
    func mayAutomaticallyShare(space: ClipboardSpace, text: String) -> Bool {
        automaticSharingEnabled && isEligible(space: space, text: text) && !connectedDeviceIDs.isEmpty
    }

    private func isEligible(space: ClipboardSpace, text: String) -> Bool {
        !isPaused && !pairedDevices.isEmpty && space == .normal &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        text.utf8.count <= OrbitalClipEnvelope.maximumUTF8Bytes
    }

    /// Entry point for the authenticated transport. Keep receiving clips
    /// in Normal and suppress retransmission to prevent cross-device echo loops.
    @discardableResult
    func receive(_ envelope: OrbitalClipEnvelope, into store: ClipboardStore) -> Bool {
        guard availability == .ready, envelope.isValid,
              !receivedClipIDs.contains(envelope.clipID),
              let device = pairedDevices.first(where: { $0.id == envelope.originDeviceID }) else { return false }
        guard store.insertOrbitalClip(envelope.text, source: device.name) else { return false }
        if receiveSoundEnabled {
            if let sound = NSSound(named: NSSound.Name("Ping")) { sound.play() }
            else { NSSound.beep() }
        }
        receivedClipIDs.insert(envelope.clipID)
        receivedClipIDOrder.append(envelope.clipID)
        if receivedClipIDOrder.count > 512 {
            let expiredID = receivedClipIDOrder.removeFirst()
            receivedClipIDs.remove(expiredID)
        }
        lastReceivedDeviceName = device.name
        return true
    }

    func addPairedDevice(_ device: OrbitalPairedDevice) {
        let safeName = String(device.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard device.signingPublicKeyX963.count == 65,
              device.signingPublicKeyX963.first == 0x04, !safeName.isEmpty else { return }
        pairedDevices.removeAll { $0.id == device.id }
        pairedDevices.append(OrbitalPairedDevice(id: device.id, name: safeName,
                                                  signingPublicKeyX963: device.signingPublicKeyX963,
                                                  pairedAt: device.pairedAt))
        persistDevices()
    }

    func revokeDevice(_ id: UUID) {
        transport?.unpairDevice(id)
        removePairedDevice(id, disconnect: false)
    }

    private func removePairedDevice(_ id: UUID, disconnect: Bool = true) {
        pairedDevices.removeAll { $0.id == id }
        connectedDeviceIDs.remove(id)
        pendingManualSends.removeValue(forKey: id)
        if disconnect { transport?.disconnectDevice(id) }
        updateAvailability()
        persistDevices()
    }

    /// Called only by the transport after its listener is active and an
    /// authenticated pairing flow has completed; never equate discovery with trust.
    func setAuthenticatedTransportAvailable(_ available: Bool) {
        if !available { connectedDeviceIDs.removeAll() }
        updateAvailability()
    }

    private func updateAvailability() {
        availability = connectedDeviceIDs.isEmpty || pairedDevices.isEmpty ? .preparation : .ready
    }

    private func persistDevices() {
        guard let data = try? JSONEncoder().encode(pairedDevices) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static var localDeviceName: String {
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "Mac"
        return String(host.prefix(64))
    }
}
