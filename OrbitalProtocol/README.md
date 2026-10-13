# Orbital protocol v1

All traffic is a direct TCP connection discovered by Bonjour and protected by TLS 1.3. Android pins the full SHA-256 fingerprint from the one-time QR before TLS. It does not trust Bonjour data for identity. The QR secret is never announced. Both peers reject unknown message fields, wrong versions, malformed lengths, expired pairing IDs, and non-paired devices. A connection is not allowed to send or receive a clip until application authentication completes.

## Framing

Every message is one UTF-8 JSON object prefixed by an unsigned 32-bit big-endian byte length. The receiver validates `1...1,600,000` before allocating the body and reads exactly that many bytes. Protocol schemas use `additionalProperties: false`. Clip envelopes and the handshake share this framing.

## Handshake order

1. Android sends `hello` with its persistent device UUID, display name, X9.63 uncompressed P-256 signing public key (65 bytes), fresh 32-byte client nonce, and (only during first pairing) the QR `pairingID`.
2. The Mac checks the pairing ID or finds an already paired device. It sends `challenge` with its persistent device UUID and a fresh 32-byte server nonce. Unknown devices without a live pairing ID are disconnected.
3. During first pairing Android sends `pair-proof`; otherwise it sends `device-proof`. The Mac authenticates this proof before accepting any other message.
4. For a first pairing, the first valid HMAC proof atomically consumes the one-use QR, so concurrent clients cannot reuse the same pairing secret. Both sides display the same six-digit comparison code. The Mac stores the new public key only after explicit approval in its UI, then sends `accepted`. Cancel/timeout sends `rejected` and discards the candidate.
5. A paired reconnect receives `accepted` only after verifying the fresh signature. A subsequent clip frame is then eligible for validation and delivery.
6. Either authenticated peer may send `unpair` with the paired Android device UUID. The receiver removes that pairing and answers `unpair-ack` with the same UUID before closing the session. Android keeps a local-only pending unlink record until the Mac acknowledges it, so an offline unlink completes the next time both devices meet on the local Wi-Fi. If the Mac initiates revocation while Android is offline, its next reconnect receives `rejected` and clears its local pairing.

## Canonical proof inputs

UUIDs are their 16 RFC 4122 bytes in network order. Integers are unsigned big-endian. Names are their exact UTF-8 bytes after the Mac's 1–64 Unicode-scalar and 256-byte UTF-8 validation. Nonces and public keys use the decoded bytes, not their base64 text. The two messages are:

```text
pairTranscript = UTF8("PasteShifter/Orbital/Pair/v1\0")
              || pairingUUID[16] || macUUID[16] || androidUUID[16]
              || clientNonce[32] || serverNonce[32] || publicKeyX963[65]
              || nameLength[2] || nameUTF8
pairProof = HMAC-SHA256(pairingSecret[32], pairTranscript)
comparisonCode = decimal6(BE32(HMAC-SHA256(pairingSecret,
                     UTF8("PasteShifter/Orbital/SAS/v1\0") || pairTranscript)[0..<4]) mod 1_000_000)

authTranscript = UTF8("PasteShifter/Orbital/Auth/v1\0")
               || macUUID[16] || androidUUID[16]
               || clientNonce[32] || serverNonce[32] || publicKeyX963[65]
               || nameLength[2] || nameUTF8
deviceProof = ECDSA-P256-SHA256-DER(androidPrivateKey, authTranscript)
```

The Mac accepts pair proofs with CryptoKit's constant-time HMAC verification and reconnect proofs with P-256 signature verification against the stored key. The fresh server nonce is one-use and expires with the connection; signatures from earlier sessions cannot authenticate a later connection. Do not log transcripts, proofs, pairing secrets, or clip text.

## Versioned schemas

- [Pairing QR v1](pairing-v1.schema.json)
- [Handshake v1](handshake-v1.schema.json)
- [Clip envelope v1](clip-envelope-v1.schema.json)

No endpoint in these schemas is a web URL. The HTTPS schema vocabulary is only a JSON Schema dialect identifier; the applications never fetch schemas or contact those domains.
