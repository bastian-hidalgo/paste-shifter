package cl.pasteshifter.orbital;

import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.AlgorithmParameters;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.cert.Certificate;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.security.KeyFactory;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Dependency-free cryptographic and framing primitives for Orbital v1.
 * Android UI, QR parsing, TLS pinning, and socket lifecycle belong to the app
 * layer. Keep these byte encodings aligned with OrbitalProtocol/README.md.
 */
public final class OrbitalProtocol {
    public static final int MAX_FRAME_BYTES = 1_600_000;
    public static final int MAX_CLIP_UTF8_BYTES = 256_000;
    private static final byte[] PAIR_DOMAIN = utf8("PasteShifter/Orbital/Pair/v1\0");
    private static final byte[] SAS_DOMAIN = utf8("PasteShifter/Orbital/SAS/v1\0");
    private static final byte[] AUTH_DOMAIN = utf8("PasteShifter/Orbital/Auth/v1\0");

    private OrbitalProtocol() {}

    public static byte[] pairTranscript(
            UUID pairingId,
            UUID macId,
            UUID androidId,
            byte[] clientNonce,
            byte[] serverNonce,
            byte[] publicKeyX963,
            String deviceName
    ) throws GeneralSecurityException {
        validateHello(clientNonce, serverNonce, publicKeyX963, deviceName);
        ByteArrayOutputStream out = new ByteArrayOutputStream(256 + utf8(deviceName).length);
        write(out, PAIR_DOMAIN);
        writeUuid(out, pairingId);
        writeUuid(out, macId);
        writeUuid(out, androidId);
        write(out, clientNonce);
        write(out, serverNonce);
        write(out, publicKeyX963);
        writeName(out, deviceName);
        return out.toByteArray();
    }

    public static byte[] pairProof(byte[] pairingSecret, byte[] pairTranscript)
            throws GeneralSecurityException {
        requireLength(pairingSecret, 32, "pairing secret");
        return hmac(pairingSecret, pairTranscript);
    }

    public static String comparisonCode(byte[] pairingSecret, byte[] pairTranscript)
            throws GeneralSecurityException {
        requireLength(pairingSecret, 32, "pairing secret");
        ByteArrayOutputStream input = new ByteArrayOutputStream(SAS_DOMAIN.length + pairTranscript.length);
        write(input, SAS_DOMAIN);
        write(input, pairTranscript);
        byte[] digest = hmac(pairingSecret, input.toByteArray());
        long firstWord = Integer.toUnsignedLong(ByteBuffer.wrap(digest, 0, 4).getInt());
        return String.format(java.util.Locale.ROOT, "%06d", firstWord % 1_000_000L);
    }

    public static byte[] authTranscript(
            UUID macId,
            UUID androidId,
            byte[] clientNonce,
            byte[] serverNonce,
            byte[] publicKeyX963,
            String deviceName
    ) throws GeneralSecurityException {
        validateHello(clientNonce, serverNonce, publicKeyX963, deviceName);
        ByteArrayOutputStream out = new ByteArrayOutputStream(256 + utf8(deviceName).length);
        write(out, AUTH_DOMAIN);
        writeUuid(out, macId);
        writeUuid(out, androidId);
        write(out, clientNonce);
        write(out, serverNonce);
        write(out, publicKeyX963);
        writeName(out, deviceName);
        return out.toByteArray();
    }

    /** Uses the Android Keystore P-256 PrivateKey; returns ASN.1 DER ECDSA. */
    public static byte[] signReconnect(PrivateKey privateKey, byte[] authTranscript)
            throws GeneralSecurityException {
        Signature signer = Signature.getInstance("SHA256withECDSA");
        signer.initSign(privateKey);
        signer.update(authTranscript);
        return signer.sign();
    }

    /** Verifies a P-256 signature using the 65-byte uncompressed X9.63 point. */
    public static boolean verifyReconnect(byte[] publicKeyX963, byte[] authTranscript, byte[] signatureDer)
            throws GeneralSecurityException {
        if (signatureDer == null || signatureDer.length < 8 || signatureDer.length > 80) return false;
        Signature verifier = Signature.getInstance("SHA256withECDSA");
        verifier.initVerify(decodeP256PublicKey(publicKeyX963));
        verifier.update(authTranscript);
        return verifier.verify(signatureDer);
    }

    public static PublicKey decodeP256PublicKey(byte[] x963) throws GeneralSecurityException {
        requireLength(x963, 65, "P-256 public key");
        if (x963[0] != 0x04) throw new GeneralSecurityException("Expected uncompressed X9.63 point");
        byte[] x = new byte[32];
        byte[] y = new byte[32];
        System.arraycopy(x963, 1, x, 0, 32);
        System.arraycopy(x963, 33, y, 0, 32);
        AlgorithmParameters parameters = AlgorithmParameters.getInstance("EC");
        parameters.init(new ECGenParameterSpec("secp256r1"));
        ECParameterSpec curve = parameters.getParameterSpec(ECParameterSpec.class);
        ECPublicKeySpec keySpec = new ECPublicKeySpec(
                new ECPoint(new BigInteger(1, x), new BigInteger(1, y)), curve);
        return KeyFactory.getInstance("EC").generatePublic(keySpec);
    }

    public static byte[] certificateFingerprint(Certificate certificate) throws GeneralSecurityException {
        return MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded());
    }

    public static boolean matchesCertificateFingerprint(Certificate certificate, byte[] expectedSha256)
            throws GeneralSecurityException {
        if (expectedSha256 == null || expectedSha256.length != 32) return false;
        return MessageDigest.isEqual(expectedSha256, certificateFingerprint(certificate));
    }

    /** Reads one bounded frame. The advertised length is checked before allocation. */
    public static byte[] readFrame(InputStream input) throws IOException {
        DataInputStream data = new DataInputStream(input);
        long length = Integer.toUnsignedLong(data.readInt());
        if (length < 1 || length > MAX_FRAME_BYTES) throw new IOException("Invalid Orbital frame length");
        byte[] body = new byte[(int) length];
        data.readFully(body);
        return body;
    }

    public static void writeFrame(OutputStream output, byte[] body) throws IOException {
        if (body == null || body.length < 1 || body.length > MAX_FRAME_BYTES) {
            throw new IOException("Invalid Orbital frame length");
        }
        DataOutputStream data = new DataOutputStream(output);
        data.writeInt(body.length);
        data.write(body);
        data.flush();
    }

    public static boolean isValidClipText(String text) {
        return text != null && !isBlankText(text)
                && text.getBytes(StandardCharsets.UTF_8).length <= MAX_CLIP_UTF8_BYTES;
    }

    public static boolean isBlankText(String value) {
        return value == null || value.codePoints().allMatch(cp -> Character.isWhitespace(cp)
                || Character.isSpaceChar(cp) || cp == 0x0085);
    }

    private static void validateHello(byte[] clientNonce, byte[] serverNonce,
                                      byte[] publicKeyX963, String deviceName)
            throws GeneralSecurityException {
        requireLength(clientNonce, 32, "client nonce");
        requireLength(serverNonce, 32, "server nonce");
        requireLength(publicKeyX963, 65, "P-256 public key");
        if (publicKeyX963[0] != 0x04) throw new GeneralSecurityException("Expected uncompressed X9.63 point");
        if (deviceName == null || deviceName.isEmpty() || deviceName.codePointCount(0, deviceName.length()) > 64
                || utf8(deviceName).length > 256 || isBlankText(deviceName)) {
            throw new GeneralSecurityException("Invalid device name");
        }
    }

    private static void writeName(ByteArrayOutputStream out, String name) throws GeneralSecurityException {
        byte[] bytes = utf8(name);
        if (bytes.length == 0 || bytes.length > 256 || bytes.length > 0xffff) {
            throw new GeneralSecurityException("Invalid device name length");
        }
        out.write((bytes.length >>> 8) & 0xff);
        out.write(bytes.length & 0xff);
        write(out, bytes);
    }

    private static void writeUuid(ByteArrayOutputStream out, UUID id) {
        ByteBuffer bytes = ByteBuffer.allocate(16);
        bytes.putLong(id.getMostSignificantBits());
        bytes.putLong(id.getLeastSignificantBits());
        write(out, bytes.array());
    }

    private static byte[] hmac(byte[] key, byte[] message) throws GeneralSecurityException {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        return mac.doFinal(message);
    }

    private static void requireLength(byte[] value, int length, String label) throws GeneralSecurityException {
        if (value == null || value.length != length) throw new GeneralSecurityException("Invalid " + label);
    }

    private static byte[] utf8(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    private static void write(ByteArrayOutputStream out, byte[] value) { out.write(value, 0, value.length); }
}
