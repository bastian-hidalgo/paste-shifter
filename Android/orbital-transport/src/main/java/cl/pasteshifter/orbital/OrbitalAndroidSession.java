package cl.pasteshifter.orbital;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.RouteInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.Log;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.SecureRandom;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * One-shot Android client session for Orbital v1. Pairing discovery, TLS pin,
 * handshake, and clip framing are implemented here; the app owns UI, clipboard
 * policy, persistence of the returned PairedMac, and reconnect scheduling.
 */
public final class OrbitalAndroidSession implements AutoCloseable {
    public interface Listener {
        void onStatus(String status);
        void onPairingComparisonCode(String code);
        void onPaired(PairedMac mac);
        void onClip(ReceivedClip clip);
        default void onUnpaired(UUID macId) {}
        default void onUnpairAcknowledged(UUID macId) {}
        default void onClosed() {}
    }

    public static final class PairedMac {
        public final UUID macId;
        public final byte[] certificateFingerprintSha256;

        public PairedMac(UUID macId, byte[] fingerprint) {
            this.macId = macId;
            this.certificateFingerprintSha256 = fingerprint.clone();
        }
    }

    public static final class ReceivedClip {
        public final UUID clipId;
        public final UUID macId;
        public final String macName;
        public final String text;
        public final long createdAtMilliseconds;

        private ReceivedClip(UUID clipId, UUID macId, String macName, String text, long createdAtMilliseconds) {
            this.clipId = clipId;
            this.macId = macId;
            this.macName = macName;
            this.text = text;
            this.createdAtMilliseconds = createdAtMilliseconds;
        }
    }

    private static final String KEY_ALIAS = "cl.pasteshifter.orbital.android-signing.v1";
    private static final String PREFS = "orbital.local.v1";
    private static final String DEVICE_ID_KEY = "device_id";

    private final Context appContext;
    private final Listener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService workers = Executors.newCachedThreadPool();
    private final ExecutorService sendQueue = new ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
            new ArrayBlockingQueue<>(32), new ThreadPoolExecutor.AbortPolicy());
    private final OrbitalDiscovery discovery;
    private final AtomicBoolean closed = new AtomicBoolean(false);
    private final Object outputLock = new Object();
    private volatile SSLSocket socket;
    private volatile OutputStream activeOutput;
    private volatile UUID deviceId;
    private volatile String deviceName;
    private volatile UUID connectedMacId;
    private volatile OrbitalPairingQr activePairingQr;

    public OrbitalAndroidSession(Context context, Listener listener) {
        this.appContext = context.getApplicationContext();
        this.listener = listener;
        this.discovery = new OrbitalDiscovery(appContext);
    }

    /** QR scan entry point. The QR secret is used only after TLS pin validation. */
    public void pairFromQr(String qrJson, String requestedDeviceName) {
        if (!begin(requestedDeviceName)) return;
        final OrbitalPairingQr qr;
        try {
            qr = OrbitalPairingQr.parse(qrJson, System.currentTimeMillis());
        } catch (JSONException e) {
            status("El código QR no es válido o ya venció.");
            close();
            return;
        }
        activePairingQr = qr;
        if (closed.get()) {
            qr.clearSecret();
            activePairingQr = null;
            return;
        }
        status("Buscando el Mac en la red local…");
        discovery.start(qr.macId, new OrbitalDiscovery.Callback() {
            @Override public void onFound(java.net.InetAddress address, int port) {
                try {
                    workers.execute(() -> connect(address, port, qr.macId, qr.certificateFingerprintSha256,
                            qr, null));
                } catch (RejectedExecutionException ignored) {}
            }
            @Override public void onFailure(String reason) { status(reason); close(); }
        });
    }

    /** Reconnect entry point. Persist the returned pin and Mac UUID locally. */
    public void reconnect(PairedMac pairedMac, String requestedDeviceName) {
        if (pairedMac == null || pairedMac.certificateFingerprintSha256.length != 32
                || !begin(requestedDeviceName)) return;
        status("Buscando el Mac emparejado en la red local…");
        discovery.start(pairedMac.macId, new OrbitalDiscovery.Callback() {
            @Override public void onFound(java.net.InetAddress address, int port) {
                try {
                    workers.execute(() -> connect(address, port, pairedMac.macId,
                            pairedMac.certificateFingerprintSha256, null, pairedMac));
                } catch (RejectedExecutionException ignored) {}
            }
            @Override public void onFailure(String reason) { status(reason); close(); }
        });
    }

    /** Queue a send after acceptance; true means queued, not acknowledged as delivered. */
    public boolean sendText(String text) {
        if (closed.get() || activeOutput == null || !OrbitalProtocol.isValidClipText(text)) return false;
        try {
            sendQueue.execute(() -> {
                try {
                    JSONObject clip = new JSONObject();
                    clip.put("version", 1);
                    clip.put("clipID", UUID.randomUUID().toString());
                    clip.put("originDeviceID", localDeviceId().toString());
                    clip.put("originDeviceName", deviceName);
                    clip.put("text", text);
                    clip.put("createdAtMilliseconds", System.currentTimeMillis());
                    byte[] json = clip.toString().getBytes(StandardCharsets.UTF_8);
                    synchronized (outputLock) {
                        if (closed.get() || activeOutput == null) return;
                        OrbitalProtocol.writeFrame(activeOutput, json);
                    }
                } catch (Exception e) {
                    if (!closed.get()) status("No se pudo enviar la copia por Orbital.");
                    close();
                }
            });
            return true;
        } catch (RejectedExecutionException e) {
            return false;
        }
    }

    /** Send an authenticated unlink notice to the currently connected Mac. */
    public boolean sendUnpair() {
        UUID macId = connectedMacId;
        if (closed.get() || activeOutput == null || macId == null) return false;
        try {
            sendQueue.execute(() -> {
                try {
                    JSONObject json = new JSONObject();
                    json.put("version", 1);
                    json.put("messageType", "unpair");
                    json.put("deviceID", localDeviceId().toString());
                    synchronized (outputLock) {
                        if (closed.get() || activeOutput == null) return;
                        OrbitalProtocol.writeFrame(activeOutput, json.toString().getBytes(StandardCharsets.UTF_8));
                    }
                } catch (Exception e) { if (!closed.get()) status("No se pudo completar la desvinculación local."); }
            });
            return true;
        } catch (RejectedExecutionException e) { return false; }
    }

    private boolean begin(String requestedName) {
        if (closed.get()) return false;
        if (Build.VERSION.SDK_INT >= 37 && appContext.getApplicationInfo().targetSdkVersion >= 37
                && appContext.checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK")
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            status("Android requiere permiso para usar la red local. Autorízalo en Paste Shifter y vuelve a intentar.");
            close();
            return false;
        }
        try {
            deviceName = validatedName(requestedName);
            localDeviceId();
            keyPair();
            return true;
        } catch (Exception e) {
            status("No se pudo preparar la identidad local de Orbital.");
            close();
            return false;
        }
    }

    private void connect(java.net.InetAddress address, int port, UUID expectedMacId,
                         byte[] pin, OrbitalPairingQr pairing, PairedMac reconnect) {
        SSLSocket candidate = null;
        try {
            if (closed.get()) return;
            if (pairing != null && !pairing.isStillValid(System.currentTimeMillis())) {
                throw new IllegalStateException("El código QR venció antes de conectar");
            }
            Network wifiNetwork = directWifiNetworkFor(address);
            if (wifiNetwork == null) {
                throw new IllegalStateException("El servicio no apunta a un dispositivo directamente conectado por Wi‑Fi");
            }
            status("Validando el certificado fijado en el QR…");
            SSLSocketFactory factory = OrbitalPinnedTls.create(pin).getSocketFactory();
            candidate = (SSLSocket) factory.createSocket();
            // Bind before connect so a route change cannot send the socket via
            // cellular, a VPN, or another default network after validation.
            wifiNetwork.bindSocket(candidate);
            candidate.setEnabledProtocols(new String[]{"TLSv1.3"});
            candidate.connect(new InetSocketAddress(address, port), 8_000);
            candidate.setSoTimeout(8_000);
            candidate.startHandshake();
            if (closed.get()) { candidate.close(); return; }
            socket = candidate;
            InputStream input = candidate.getInputStream();
            OutputStream output = candidate.getOutputStream();

            KeyPair keys = keyPair();
            byte[] publicKey = encodeX963((ECPublicKey) keys.getPublic());
            byte[] clientNonce = new byte[32];
            new SecureRandom().nextBytes(clientNonce);
            JSONObject hello = new JSONObject();
            hello.put("version", 1);
            hello.put("messageType", "hello");
            hello.put("deviceID", localDeviceId().toString());
            hello.put("deviceName", deviceName);
            hello.put("signingPublicKeyX963", base64(publicKey));
            hello.put("clientNonce", base64(clientNonce));
            if (pairing != null) hello.put("pairingID", pairing.pairingId.toString());
            writeJson(output, hello);

            JSONObject challenge = readJson(input);
            if ("rejected".equals(challenge.optString("messageType"))) {
                throw new IllegalStateException("El Mac ya no reconoce este teléfono. Vuelve a vincularlo.");
            }
            requireFields(challenge, "version", "messageType", "localDeviceID", "serverNonce");
            requireVersionAndType(challenge, "challenge");
            UUID macId = strictUuid(challenge, "localDeviceID");
            if (!macId.equals(expectedMacId)) throw new JSONException("Unexpected Mac identity");
            byte[] serverNonce = decodeBase64(challenge, "serverNonce", 32);

            if (pairing != null) {
                if (!pairing.isStillValid(System.currentTimeMillis())) throw new JSONException("Pairing QR expired");
                byte[] transcript = OrbitalProtocol.pairTranscript(pairing.pairingId, macId,
                        localDeviceId(), clientNonce, serverNonce, publicKey, deviceName);
                String expectedCode;
                byte[] proofBytes;
                try {
                    expectedCode = OrbitalProtocol.comparisonCode(pairing.pairingSecret, transcript);
                    proofBytes = OrbitalProtocol.pairProof(pairing.pairingSecret, transcript);
                } finally {
                    pairing.clearSecret();
                }
                JSONObject proof = new JSONObject();
                proof.put("version", 1);
                proof.put("messageType", "pair-proof");
                proof.put("pairingID", pairing.pairingId.toString());
                proof.put("proofHMACSHA256", base64(proofBytes));
                writeJson(output, proof);

                candidate.setSoTimeout(65_000);
                JSONObject approval = readJson(input);
                requireFields(approval, "version", "messageType", "comparisonCode");
                requireVersionAndType(approval, "approval-needed");
                String receivedCode = strictString(approval, "comparisonCode");
                if (!receivedCode.matches("[0-9]{6}") || !receivedCode.equals(expectedCode)) {
                    throw new JSONException("Pairing comparison code mismatch");
                }
                mainHandler.post(() -> listener.onPairingComparisonCode(receivedCode));
            } else {
                byte[] transcript = OrbitalProtocol.authTranscript(macId, localDeviceId(), clientNonce,
                        serverNonce, publicKey, deviceName);
                JSONObject proof = new JSONObject();
                proof.put("version", 1);
                proof.put("messageType", "device-proof");
                proof.put("signatureDER", base64(OrbitalProtocol.signReconnect(keys.getPrivate(), transcript)));
                writeJson(output, proof);
                candidate.setSoTimeout(10_000);
            }

            JSONObject reply = readJson(input);
            requireFields(reply, "version", "messageType", "deviceID");
            String replyType = strictString(reply, "messageType");
            requireVersion(reply);
            if ("rejected".equals(replyType)) throw new IllegalStateException("El Mac rechazó el emparejamiento");
            if (!"accepted".equals(replyType)
                    || !localDeviceId().equals(strictUuid(reply, "deviceID"))) {
                throw new JSONException("Invalid Orbital acceptance");
            }
            connectedMacId = macId;
            activeOutput = output;
            candidate.setSoTimeout(0);
            status("Conectado al Mac por una sesión TLS 1.3 fijada y autenticada.");
            if (pairing != null) {
                PairedMac pairedMac = new PairedMac(macId, pin);
                mainHandler.post(() -> listener.onPaired(pairedMac));
            }
            readClips(input, macId);
        } catch (Exception e) {
            Throwable root = e;
            while (root.getCause() != null && root.getCause() != root) root = root.getCause();
            String detail = root instanceof java.security.cert.CertificateException
                    ? ": " + root.getMessage() : "";
            Log.w("OrbitalSession", "Local secure connection failed: "
                    + e.getClass().getSimpleName() + " ("
                    + root.getClass().getSimpleName() + detail + ")");
            if (!closed.get()) {
                if (root instanceof java.security.cert.CertificateException
                        && "Mac certificate pin mismatch".equals(root.getMessage())) {
                    status("El certificado seguro del Mac cambió. Vuelve a emparejarlo con un nuevo código QR.");
                } else if (e instanceof IllegalStateException && e.getMessage() != null
                        && e.getMessage().startsWith("El Mac ya no reconoce")) {
                    status(e.getMessage());
                } else {
                    status("No se pudo establecer la conexión Orbital segura.");
                }
            }
            close();
        } finally {
            if (pairing != null) {
                pairing.clearSecret();
                if (activePairingQr == pairing) activePairingQr = null;
            }
            if (candidate != null && candidate != socket) {
                try { candidate.close(); } catch (Exception ignored) {}
            }
        }
    }

    private void readClips(InputStream input, UUID macId) throws Exception {
        while (!closed.get()) {
            JSONObject json = readJson(input);
            String messageType = json.optString("messageType", "");
            if ("unpair".equals(messageType)) {
                requireFields(json, "version", "messageType", "deviceID");
                requireVersion(json);
                UUID deviceId = strictUuid(json, "deviceID");
                if (!deviceId.equals(localDeviceId())) throw new JSONException("Invalid unlink device identity");
                JSONObject ack = new JSONObject(); ack.put("version", 1); ack.put("messageType", "unpair-ack");
                ack.put("deviceID", deviceId.toString());
                synchronized (outputLock) { if (!closed.get() && activeOutput != null) OrbitalProtocol.writeFrame(activeOutput, ack.toString().getBytes(StandardCharsets.UTF_8)); }
                mainHandler.post(() -> listener.onUnpaired(macId));
                return;
            }
            if ("unpair-ack".equals(messageType)) {
                requireFields(json, "version", "messageType", "deviceID");
                requireVersion(json);
                UUID deviceId = strictUuid(json, "deviceID");
                if (!deviceId.equals(localDeviceId())) throw new JSONException("Invalid unlink acknowledgement identity");
                mainHandler.post(() -> listener.onUnpairAcknowledged(macId));
                return;
            }
            requireFields(json, "version", "clipID", "originDeviceID", "originDeviceName", "text",
                    "createdAtMilliseconds");
            requireVersion(json);
            UUID clipId = strictUuid(json, "clipID");
            UUID origin = strictUuid(json, "originDeviceID");
            String name = strictString(json, "originDeviceName");
            String text = strictString(json, "text");
            Object timestampValue = json.opt("createdAtMilliseconds");
            if (!(timestampValue instanceof Number)
                    || ((Number) timestampValue).doubleValue() != ((Number) timestampValue).longValue()) {
                throw new JSONException("Invalid clip timestamp");
            }
            long timestamp = ((Number) timestampValue).longValue();
            if (!origin.equals(macId) || !OrbitalProtocol.isValidClipText(text)
                    || name.isEmpty() || name.codePointCount(0, name.length()) > 64
                    || name.getBytes(StandardCharsets.UTF_8).length > 256 || timestamp < 0) {
                throw new JSONException("Invalid Orbital clip");
            }
            ReceivedClip clip = new ReceivedClip(clipId, origin, name, text, timestamp);
            mainHandler.post(() -> listener.onClip(clip));
        }
    }

    private KeyPair keyPair() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (keyStore.containsAlias(KEY_ALIAS)) {
            PrivateKey privateKey = (PrivateKey) keyStore.getKey(KEY_ALIAS, null);
            java.security.cert.Certificate certificate = keyStore.getCertificate(KEY_ALIAS);
            if (privateKey != null && certificate != null) {
                return new KeyPair(certificate.getPublicKey(), privateKey);
            }
            throw new IllegalStateException("Incomplete Android Keystore identity");
        }
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC", "AndroidKeyStore");
        KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false)
                .build();
        generator.initialize(spec);
        return generator.generateKeyPair();
    }

    private UUID localDeviceId() {
        UUID value = deviceId;
        if (value != null) return value;
        synchronized (this) {
            if (deviceId == null) {
                SharedPreferences preferences = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
                String stored = preferences.getString(DEVICE_ID_KEY, null);
                UUID parsed;
                try { parsed = stored == null ? UUID.randomUUID() : UUID.fromString(stored); }
                catch (IllegalArgumentException e) { parsed = UUID.randomUUID(); }
                preferences.edit().putString(DEVICE_ID_KEY, parsed.toString()).apply();
                deviceId = parsed;
            }
            return deviceId;
        }
    }

    /** Refuse Bonjour targets that route through a gateway, VPN, mobile data, or Internet. */
    private Network directWifiNetworkFor(InetAddress address) {
        if (address == null || address.isAnyLocalAddress() || address.isLoopbackAddress()
                || address.isMulticastAddress()) return null;
        ConnectivityManager connectivity = (ConnectivityManager)
                appContext.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (connectivity == null) return null;
        Network network = connectivity.getActiveNetwork();
        if (network == null) return null;
        NetworkCapabilities capabilities = connectivity.getNetworkCapabilities(network);
        if (capabilities == null || !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return null;
        LinkProperties properties = connectivity.getLinkProperties(network);
        if (properties == null) return null;
        for (RouteInfo route : properties.getRoutes()) {
            if (!route.hasGateway() && route.getDestination().contains(address)) return network;
        }
        return null;
    }

    private static byte[] encodeX963(ECPublicKey key) {
        byte[] result = new byte[65];
        result[0] = 0x04;
        byte[] x = fixed32(key.getW().getAffineX().toByteArray());
        byte[] y = fixed32(key.getW().getAffineY().toByteArray());
        System.arraycopy(x, 0, result, 1, 32);
        System.arraycopy(y, 0, result, 33, 32);
        return result;
    }

    private static byte[] fixed32(byte[] value) {
        int offset = value.length == 33 && value[0] == 0 ? 1 : 0;
        int length = value.length - offset;
        if (length > 32) throw new IllegalArgumentException("Invalid P-256 coordinate");
        byte[] out = new byte[32];
        System.arraycopy(value, offset, out, 32 - length, length);
        return out;
    }

    private static String validatedName(String input) {
        String name = input == null || OrbitalProtocol.isBlankText(input) ? "Android" : input;
        if (name.codePointCount(0, name.length()) > 64 || name.getBytes(StandardCharsets.UTF_8).length > 256) {
            throw new IllegalArgumentException("Device name too long");
        }
        return name;
    }

    private static void writeJson(OutputStream output, JSONObject json) throws Exception {
        OrbitalProtocol.writeFrame(output, json.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static JSONObject readJson(InputStream input) throws Exception {
        byte[] frame = OrbitalProtocol.readFrame(input);
        if (frame.length > OrbitalProtocol.MAX_FRAME_BYTES) throw new JSONException("Frame too large");
        String body = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(frame)).toString();
        return new JSONObject(body);
    }

    private static String base64(byte[] data) { return Base64.encodeToString(data, Base64.NO_WRAP); }

    private static byte[] decodeBase64(JSONObject json, String key, int expectedLength) throws JSONException {
        byte[] value;
        String encoded = strictString(json, key);
        try { value = Base64.decode(encoded, Base64.NO_WRAP); }
        catch (IllegalArgumentException e) { throw new JSONException("Invalid base64 field " + key); }
        if (value.length != expectedLength || !base64(value).equals(encoded)) {
            throw new JSONException("Invalid length or encoding for " + key);
        }
        return value;
    }

    private static UUID strictUuid(JSONObject json, String key) throws JSONException {
        String value = strictString(json, key);
        if (!value.matches("(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")) {
            throw new JSONException("Invalid UUID field " + key);
        }
        return UUID.fromString(value);
    }

    private static String strictString(JSONObject json, String key) throws JSONException {
        Object value = json.opt(key);
        if (!(value instanceof String)) throw new JSONException("Expected string field " + key);
        return (String) value;
    }

    private static void requireVersionAndType(JSONObject json, String type) throws JSONException {
        requireVersion(json);
        if (!type.equals(strictString(json, "messageType"))) throw new JSONException("Unexpected message type");
    }

    private static void requireVersion(JSONObject json) throws JSONException {
        Object value = json.opt("version");
        if (!(value instanceof Number) || ((Number) value).intValue() != 1
                || ((Number) value).doubleValue() != 1.0) throw new JSONException("Unsupported protocol version");
    }

    private static void requireFields(JSONObject json, String... expected) throws JSONException {
        Set<String> fields = new HashSet<>(Arrays.asList(expected));
        Iterator<String> keys = json.keys();
        while (keys.hasNext()) if (!fields.remove(keys.next())) throw new JSONException("Unexpected message field");
        if (!fields.isEmpty()) throw new JSONException("Missing message field");
    }

    private void status(String message) { mainHandler.post(() -> listener.onStatus(message)); }

    @Override public void close() {
        if (!closed.compareAndSet(false, true)) return;
        discovery.stop();
        OrbitalPairingQr pairing = activePairingQr;
        activePairingQr = null;
        if (pairing != null) pairing.clearSecret();
        activeOutput = null;
        SSLSocket active = socket;
        socket = null;
        if (active != null) try { active.close(); } catch (Exception ignored) {}
        workers.shutdownNow();
        sendQueue.shutdownNow();
        mainHandler.post(listener::onClosed);
    }
}
