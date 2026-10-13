import Foundation
import Network
import Security

struct OrbitalPairingRequest: Identifiable {
    let id: UUID
    let deviceID: UUID
    let deviceName: String
    let signingPublicKeyX963: Data
    let comparisonCode: String
}

/// Direct Wi-Fi listener. It advertises only a device UUID, never the QR
/// secret or clipboard data. TLS pins the Mac at scan time; this class then
/// authenticates each phone before accepting a clip frame.
final class OrbitalLocalTransport {
    private let queue = DispatchQueue(label: "cl.pasteshifter.orbital.transport", qos: .userInitiated)
    private var listener: NWListener?
    private var pendingPairing: OrbitalPairingPayload?
    private var sessions: [UUID: ConnectionSession] = [:]
    private var attempts: [Date] = []
    private var localIdentity: OrbitalLocalIdentity?
    private let localDeviceID: UUID
    private let pairedDevices: () -> [OrbitalPairedDevice]

    var onState: ((String) -> Void)?
    var onPairingRequest: ((OrbitalPairingRequest, @escaping (Bool) -> Void) -> Void)?
    var onPairingCancelled: ((UUID) -> Void)?
    var onIncomingClip: ((OrbitalClipEnvelope) -> Void)?
    var onUnpair: ((UUID) -> Void)?
    var onListenerReady: (() -> Void)?
    var onAuthenticated: ((UUID, String) -> Void)?
    var onDisconnected: ((UUID) -> Void)?

    init(localDeviceID: UUID, pairedDevices: @escaping () -> [OrbitalPairedDevice]) {
        self.localDeviceID = localDeviceID
        self.pairedDevices = pairedDevices
    }

    func start(pairing payload: OrbitalPairingPayload, identity: OrbitalLocalIdentity) {
        queue.async {
            guard payload.isValid(), payload.localDeviceID == self.localDeviceID else {
                self.publishState("El código de emparejamiento venció. Genera uno nuevo.")
                return
            }
            // A listener keeps the TLS identity captured when it was created.
            // If Keychain returned a newer identity for this QR, recreate the
            // listener before advertising the QR's fingerprint; otherwise the
            // phone correctly rejects the old certificate as a pin mismatch.
            if let currentIdentity = self.localIdentity,
               currentIdentity.certificateSHA256 != identity.certificateSHA256,
               self.listener != nil {
                NSLog("Orbital TLS identity changed; restarting the local listener before pairing.")
                self.stopOnQueue()
            }
            self.pendingPairing = payload
            self.localIdentity = identity
            self.startListenerOnQueue()
        }
    }

    func resumeForPairedDevices() {
        queue.async {
            self.pendingPairing = nil
            self.startListenerOnQueue()
        }
    }

    private func startListenerOnQueue() {
        guard listener == nil else {
            publishState("Esperando un dispositivo en esta red Wi‑Fi…")
            return
        }
        publishState("Preparando conexión local segura…")
        do {
            let identity: OrbitalLocalIdentity
            if let currentIdentity = localIdentity {
                identity = currentIdentity
            } else {
                identity = try OrbitalLocalIdentity.loadOrCreate()
                localIdentity = identity
            }
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
            guard let localID = sec_identity_create(identity.secIdentity) else {
                throw TransportError.identityUnavailable
            }
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, localID)
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = 8
            let parameters = NWParameters(tls: tls, tcp: tcp)
            parameters.requiredInterfaceType = .wifi
            let listener = try NWListener(using: parameters, on: .any)
            listener.service = NWListener.Service(name: localDeviceID.uuidString,
                                                  type: "_orbital._tcp", domain: nil,
                                                  txtRecord: NWTXTRecord(["v": "1"]))
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publishState("Esperando un dispositivo en esta red Wi‑Fi…")
                    DispatchQueue.main.async { self.onListenerReady?() }
                case .failed:
                    self.publishState("No se pudo abrir la conexión local.")
                    self.stopOnQueue()
                case .cancelled:
                    self.publishState("Orbital está detenido.")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            NSLog("Orbital listener identity error: %@", String(reflecting: error))
            publishState("No se pudo preparar la identidad local de Orbital.")
            stopOnQueue()
        }
    }

    func stopPairing() {
        queue.async {
            self.pendingPairing = nil
            if self.sessions.values.allSatisfy({ !$0.isAuthenticated }) {
                self.stopOnQueue()
            } else {
                self.publishState("Emparejamiento cerrado; los dispositivos autorizados siguen conectados.")
            }
        }
    }

    func stop() {
        queue.async {
            self.pendingPairing = nil
            self.stopOnQueue()
        }
    }

    func disconnectDevice(_ deviceID: UUID) {
        queue.async {
            for session in Array(self.sessions.values) where session.deviceID == deviceID || session.device?.id == deviceID {
                self.close(session)
            }
        }
    }

    func unpairDevice(_ deviceID: UUID) {
        queue.async {
            let targets = Array(self.sessions.values).filter { $0.isAuthenticated && $0.deviceID == deviceID }
            guard let frame = try? OrbitalWireCodec.encode(OrbitalUnpairMessage(deviceID: deviceID)) else {
                targets.forEach(self.close); return
            }
            for session in targets {
                session.connection.send(content: frame, completion: .contentProcessed { [weak self, weak session] _ in
                    guard let self, let session else { return }
                    self.close(session)
                })
            }
        }
    }

    func send(_ envelope: OrbitalClipEnvelope, to deviceID: UUID? = nil) {
        guard envelope.isValid else { return }
        queue.async {
            guard let frame = try? OrbitalWireCodec.encode(envelope) else { return }
            for session in self.sessions.values where session.isAuthenticated
                    && session.deviceID != envelope.originDeviceID
                    && (deviceID == nil || session.deviceID == deviceID) {
                session.connection.send(content: frame, completion: .contentProcessed { error in
                    guard error != nil else { return }
                    self.close(session)
                })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let now = Date()
        attempts.removeAll { now.timeIntervalSince($0) > 60 }
        guard attempts.count < 30, sessions.count < 8 else {
            connection.cancel()
            return
        }
        attempts.append(now)
        let session = ConnectionSession(id: UUID(), connection: connection)
        sessions[session.id] = session
        connection.stateUpdateHandler = { [weak self, weak session] state in
            guard let self, let session else { return }
            switch state {
            case .ready:
                self.readFrame(from: session.connection, timeout: 8) { result in
                    switch result {
                    case .success(let frame): self.receiveHello(frame, from: session)
                    case .failure: self.close(session)
                    }
                }
            case .failed, .cancelled:
                self.close(session)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak session] in
            guard let self, let session, !session.isAuthenticated,
                  !session.isAwaitingApproval, !session.isFinished else { return }
            self.close(session)
        }
    }

    private func receiveHello(_ frame: Data, from session: ConnectionSession) {
        guard let hello = try? OrbitalWireCodec.decode(OrbitalClientHello.self, frame: frame),
              hello.isValid, hello.deviceID != localDeviceID else {
            close(session)
            return
        }
        session.hello = hello
        session.serverNonce = Self.randomBytes(count: 32)
        guard let nonce = session.serverNonce,
              let challenge = try? OrbitalWireCodec.encode(OrbitalServerChallenge(localDeviceID: localDeviceID,
                                                                                     serverNonce: nonce)) else {
            close(session)
            return
        }
        let pairing = pendingPairing
        if let pairingID = hello.pairingID {
            guard let pairing, pairing.pairingID == pairingID, pairing.isValid() else {
                close(session)
                return
            }
            session.pairing = pairing
            session.isPairing = true
        } else {
            guard let paired = pairedDevices().first(where: { $0.id == hello.deviceID }) else {
                // The TLS certificate has already been pinned by the client.
                // Tell that authenticated client its saved pairing was revoked
                // instead of silently making it retry forever.
                if let rejection = try? OrbitalWireCodec.encode(OrbitalHandshakeReply(rejected: hello.deviceID)) {
                    session.connection.send(content: rejection, completion: .contentProcessed { [weak self, weak session] _ in
                        guard let self, let session else { return }
                        self.close(session)
                    })
                } else { close(session) }
                return
            }
            guard paired.signingPublicKeyX963 == hello.signingPublicKeyX963 else {
                close(session)
                return
            }
            session.device = paired
        }
        session.connection.send(content: challenge, completion: .contentProcessed { [weak self, weak session] error in
            guard let self, let session else { return }
            if error != nil { self.close(session); return }
            self.readFrame(from: session.connection, timeout: 8) { result in
                switch result {
                case .success(let proof): self.receiveProof(proof, from: session)
                case .failure: self.close(session)
                }
            }
        })
    }

    private func receiveProof(_ frame: Data, from session: ConnectionSession) {
        guard let hello = session.hello, let nonce = session.serverNonce else { close(session); return }
        if session.isPairing {
            guard let pairing = session.pairing,
                  // Multiple clients can complete TLS and send hello before
                  // the first one proves possession. Only the connection that
                  // still owns the live, unconsumed QR may claim this pairing.
                  pendingPairing?.pairingID == pairing.pairingID,
                  let proof = try? OrbitalWireCodec.decode(OrbitalPairProof.self, frame: frame),
                  proof.pairingID == pairing.pairingID, pairing.isValid(),
                  OrbitalHandshake.verifyPairProof(proof.proofHMACSHA256, secret: pairing.pairingSecret,
                                                   pairingID: pairing.pairingID, localDeviceID: localDeviceID,
                                                   hello: hello, serverNonce: nonce),
                  let code = try? OrbitalHandshake.comparisonCode(secret: pairing.pairingSecret,
                                                                  pairingID: pairing.pairingID,
                                                                  localDeviceID: localDeviceID,
                                                                  hello: hello, serverNonce: nonce) else {
                close(session)
                return
            }
            // The QR is consumed after its first valid proof, before asking for
            // approval, so a second LAN client cannot race the same pairing ID.
            pendingPairing = nil
            session.pairing = nil
            session.device = OrbitalPairedDevice(id: hello.deviceID, name: hello.deviceName,
                                                  signingPublicKeyX963: hello.signingPublicKeyX963,
                                                  pairedAt: Date())
            session.approvalID = UUID()
            session.isAwaitingApproval = true
            queue.asyncAfter(deadline: .now() + 60) { [weak self, weak session] in
                guard let self, let session, session.isAwaitingApproval, !session.isFinished else { return }
                self.close(session)
            }
            let notice = OrbitalApprovalNotice(comparisonCode: code)
            guard let data = try? OrbitalWireCodec.encode(notice) else { close(session); return }
            session.connection.send(content: data, completion: .contentProcessed { error in
                if error != nil { self.close(session); return }
                guard let requestID = session.approvalID, let device = session.device,
                      let callback = self.onPairingRequest else { self.close(session); return }
                let request = OrbitalPairingRequest(id: requestID, deviceID: device.id,
                                                    deviceName: device.name,
                                                    signingPublicKeyX963: device.signingPublicKeyX963,
                                                    comparisonCode: code)
                DispatchQueue.main.async {
                    callback(request) { approved in
                        self.queue.async { self.finishPairing(approved, session: session) }
                    }
                }
            })
        } else {
            guard let device = session.device,
                  let proof = try? OrbitalWireCodec.decode(OrbitalDeviceProof.self, frame: frame),
                  OrbitalHandshake.verifyDeviceSignature(proof.signatureDER, localDeviceID: localDeviceID,
                                                         hello: hello, serverNonce: nonce,
                                                         trustedPublicKey: device.signingPublicKeyX963) else {
                close(session)
                return
            }
            acceptAuthenticated(session)
        }
    }

    private func finishPairing(_ approved: Bool, session: ConnectionSession) {
        guard !session.isFinished, session.isAwaitingApproval,
              let device = session.device, let reply = try? OrbitalWireCodec.encode(
                approved ? OrbitalHandshakeReply(accepted: device.id) : OrbitalHandshakeReply(rejected: device.id)
              ) else {
            close(session)
            return
        }
        session.isAwaitingApproval = false
        guard approved else {
            session.connection.send(content: reply, completion: .contentProcessed { [weak self, weak session] _ in
                guard let self, let session else { return }
                self.close(session)
            })
            return
        }
        acceptAuthenticated(session, reply: reply)
    }

    private func acceptAuthenticated(_ session: ConnectionSession, reply: Data? = nil) {
        guard let hello = session.hello, let device = session.device else { close(session); return }
        let reply = reply ?? (try? OrbitalWireCodec.encode(OrbitalHandshakeReply(accepted: device.id)))
        guard let reply else { close(session); return }
        session.isAuthenticated = true
        session.deviceID = hello.deviceID
        session.deviceName = device.name
        session.connection.send(content: reply, completion: .contentProcessed { [weak self, weak session] error in
            guard let self, let session else { return }
            if error != nil { self.close(session); return }
            self.readNextClip(from: session)
        })
        DispatchQueue.main.async { self.onAuthenticated?(hello.deviceID, device.name) }
        publishState("Conexión autenticada con \(device.name).")
    }

    private func readNextClip(from session: ConnectionSession) {
        // Keep authenticated paired sessions alive while the clipboard is
        // idle. The peer is already trusted and the frame length remains
        // bounded before the body is read.
        readFrame(from: session.connection, timeout: nil) { result in
            switch result {
            case .failure:
                self.close(session)
            case .success(let frame):
                if let unlink = try? OrbitalWireCodec.decode(OrbitalUnpairMessage.self, frame: frame),
                   unlink.deviceID == session.deviceID,
                   session.acceptMessage(at: Date()),
                   let ack = try? OrbitalWireCodec.encode(OrbitalUnpairAck(deviceID: unlink.deviceID)) {
                    session.connection.send(content: ack, completion: .contentProcessed { [weak self, weak session] _ in
                        guard let self, let session else { return }
                        DispatchQueue.main.async { self.onUnpair?(unlink.deviceID) }
                        self.close(session)
                    })
                    return
                }
                guard let clip = try? OrbitalWireCodec.decodeClip(frame),
                      clip.originDeviceID == session.deviceID,
                      session.acceptMessage(at: Date()) else {
                    self.close(session)
                    return
                }
                DispatchQueue.main.async { self.onIncomingClip?(clip) }
                self.readNextClip(from: session)
            }
        }
    }

    private func readFrame(from connection: NWConnection, timeout: TimeInterval?,
                           completion: @escaping (Result<Data, Error>) -> Void) {
        // All connection callbacks and this timeout run on `queue`. Gate the
        // completion so a timeout racing a receive callback cannot advance the
        // protocol state machine twice.
        var completed = false
        var timeoutItem: DispatchWorkItem?
        func finish(_ result: Result<Data, Error>) {
            guard !completed else { return }
            completed = true
            timeoutItem?.cancel()
            completion(result)
        }
        if let timeout {
            timeoutItem = DispatchWorkItem {
                finish(.failure(TransportError.timeout))
                connection.cancel()
            }
            if let timeoutItem { queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem) }
        }
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, isComplete, error in
            guard error == nil, !isComplete, let header, header.count == 4 else {
                finish(.failure(error ?? TransportError.malformedFrame))
                return
            }
            let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= OrbitalWireCodec.maximumJSONBytes else {
                finish(.failure(TransportError.malformedFrame))
                connection.cancel()
                return
            }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, complete, bodyError in
                guard bodyError == nil, !complete, let body, body.count == Int(length) else {
                    finish(.failure(bodyError ?? TransportError.malformedFrame))
                    return
                }
                var frame = header
                frame.append(body)
                finish(.success(frame))
            }
        }
    }

    private func close(_ session: ConnectionSession) {
        guard !session.isFinished else { return }
        let cancelledApprovalID = session.isAwaitingApproval ? session.approvalID : nil
        session.isAwaitingApproval = false
        session.isFinished = true
        sessions.removeValue(forKey: session.id)
        session.connection.stateUpdateHandler = nil
        session.connection.cancel()
        if session.isAuthenticated, let deviceID = session.deviceID {
            DispatchQueue.main.async { self.onDisconnected?(deviceID) }
        }
        if let cancelledApprovalID {
            DispatchQueue.main.async { self.onPairingCancelled?(cancelledApprovalID) }
        }
    }

    private func stopOnQueue() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for session in Array(sessions.values) { close(session) }
        localIdentity = nil
    }

    private func publishState(_ value: String) { DispatchQueue.main.async { self.onState?(value) } }

    private static func randomBytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private enum TransportError: Error { case identityUnavailable, timeout, malformedFrame }

    private final class ConnectionSession {
        let id: UUID
        let connection: NWConnection
        var hello: OrbitalClientHello?
        var serverNonce: Data?
        var pairing: OrbitalPairingPayload?
        var device: OrbitalPairedDevice?
        var deviceID: UUID?
        var deviceName: String?
        var approvalID: UUID?
        var isPairing = false
        var isAwaitingApproval = false
        var isAuthenticated = false
        var isFinished = false
        private var messageWindowStart = Date()
        private var messageCount = 0

        init(id: UUID, connection: NWConnection) { self.id = id; self.connection = connection }

        func acceptMessage(at date: Date) -> Bool {
            if date.timeIntervalSince(messageWindowStart) >= 60 {
                messageWindowStart = date
                messageCount = 0
            }
            messageCount += 1
            return messageCount <= 120
        }
    }
}
