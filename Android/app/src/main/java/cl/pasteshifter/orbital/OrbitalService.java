package cl.pasteshifter.orbital;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PersistableBundle;
import android.service.quicksettings.TileService;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import java.util.UUID;

/** User-started, local-only Orbital connection. No activity lifetime dependency. */
public final class OrbitalService extends Service {
    public static final String ACTION_START = "cl.pasteshifter.orbital.START";
    public static final String ACTION_PAUSE = "cl.pasteshifter.orbital.PAUSE";
    public static final String ACTION_RESUME = "cl.pasteshifter.orbital.RESUME";
    public static final String ACTION_STOP = "cl.pasteshifter.orbital.STOP";
    public static final String ACTION_FORGET_PAIRING = "cl.pasteshifter.orbital.FORGET_PAIRING";
    public static final String ACTION_SEND_TEXT = "cl.pasteshifter.orbital.SEND_TEXT";
    public static final String ACTION_CLIPBOARD_TEXT = "cl.pasteshifter.orbital.CLIPBOARD_TEXT";
    public static final String ACTION_STATUS = "cl.pasteshifter.orbital.STATUS";
    public static final String ACTION_CLIP = "cl.pasteshifter.orbital.CLIP";
    public static final String EXTRA_STATUS = "status";
    public static final String EXTRA_TEXT = "text";
    private static final String PREFS = "orbital-device.v1";
    private static final String KEY_MAC_ID = "paired_mac_id";
    private static final String KEY_PIN = "paired_mac_pin";
    private static final String KEY_REPAIR_REQUIRED = "paired_mac_repair_required";
    private static final String KEY_ACTIVE = "orbital_active";
    private static final String KEY_PENDING_MAC_ID = "pending_unpair_mac_id";
    private static final String KEY_PENDING_PIN = "pending_unpair_pin";
    private static final String CHANNEL = "orbital_connection";
    private static final String RECEIVE_CHANNEL = "orbital_received_v1";
    private static final int NOTIFICATION_ID = 7301;
    private static final int RECEIVE_NOTIFICATION_ID = 7302;
    private static volatile boolean connectionReady;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private OrbitalAndroidSession session;
    private int generation = 0;
    private boolean active;
    private boolean connected;
    private ConnectivityManager connectivity;
    private ConnectivityManager.NetworkCallback networkCallback;
    private Runnable retry;
    private String pendingText;
    private android.content.BroadcastReceiver clipboardReceiver;
    private boolean clipboardReceiverRegistered;

    public static void start(Context context) {
        Intent intent = new Intent(context, OrbitalService.class).setAction(ACTION_START);
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent); else context.startService(intent);
    }
    public static void pause(Context context) { context.startService(new Intent(context, OrbitalService.class).setAction(ACTION_PAUSE)); }
    public static void resume(Context context) { start(context); }
    public static void stop(Context context) { context.startService(new Intent(context, OrbitalService.class).setAction(ACTION_STOP)); }
    public static void forgetPairing(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE);
        String id = prefs.getString(KEY_MAC_ID, null), pin = prefs.getString(KEY_PIN, null);
        SharedPreferences.Editor edit = prefs.edit().remove(KEY_MAC_ID).remove(KEY_PIN).putBoolean(KEY_ACTIVE, false);
        if (id != null && pin != null && pin.matches("[0-9a-f]{64}")) edit.putString(KEY_PENDING_MAC_ID, id).putString(KEY_PENDING_PIN, pin);
        edit.apply();
        Intent intent = new Intent(context, OrbitalService.class).setAction(ACTION_FORGET_PAIRING);
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent); else context.startService(intent);
    }
    public static void sendText(Context context, String text) {
        Intent intent = new Intent(context, OrbitalService.class).setAction(ACTION_SEND_TEXT)
                .putExtra(EXTRA_TEXT, text);
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent); else context.startService(intent);
    }
    public static boolean hasPendingRevocation(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, MODE_PRIVATE);
        return p.contains(KEY_PENDING_MAC_ID) && p.contains(KEY_PENDING_PIN);
    }
    public static void resumePendingRevocation(Context context) {
        if (!hasPendingRevocation(context)) return;
        Intent intent = new Intent(context, OrbitalService.class).setAction(ACTION_FORGET_PAIRING);
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent); else context.startService(intent);
    }

    static ClipData sensitiveTextClip(String label, String text) {
        ClipData clip = ClipData.newPlainText(label, text);
        PersistableBundle extras = new PersistableBundle();
        String key = Build.VERSION.SDK_INT >= 33
                ? ClipDescription.EXTRA_IS_SENSITIVE : "android.content.extra.IS_SENSITIVE";
        extras.putBoolean(key, true);
        clip.getDescription().setExtras(extras);
        return clip;
    }

    @Override public void onCreate() {
        super.onCreate();
        createChannel();
        connectivity = (ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override public void onAvailable(Network network) { if (shouldRun() && hasWifi()) connect(); }
            @Override public void onLost(Network network) { if (shouldRun()) { connected = false; connectionReady = false; closeSession(); publish("Fuera de la Wi‑Fi del Mac. Orbital volverá a conectar automáticamente."); scheduleRetry(); } }
            @Override public void onCapabilitiesChanged(Network network, NetworkCapabilities caps) { if (shouldRun() && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) connect(); }
        };
        try { connectivity.registerDefaultNetworkCallback(networkCallback); } catch (RuntimeException ignored) {}
        clipboardReceiver = new android.content.BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                if (!active || intent == null || !ACTION_CLIPBOARD_TEXT.equals(intent.getAction())) return;
                String text = intent.getStringExtra(EXTRA_TEXT);
                if (text == null || !OrbitalProtocol.isValidClipText(text)) return;
                if (session != null && connected && session.sendText(text)) publish("Copia enviada al Mac por Orbital.");
                else pendingText = text;
            }
        };
        IntentFilter clipFilter = new IntentFilter(ACTION_CLIPBOARD_TEXT);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(clipboardReceiver, clipFilter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(clipboardReceiver, clipFilter);
        clipboardReceiverRegistered = true;
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_FORGET_PAIRING.equals(action)) {
            active = false; connectionReady = false; saveActive(false);
            if (!hasPendingRevocation()) { connected = false; closeSession(); stopForeground(true); publish("Mac eliminado."); stopSelf(); return START_NOT_STICKY; }
            startForeground(NOTIFICATION_ID, notification("Quitando el vínculo en tu Mac por la red local…", false));
            if (session != null && connected) { if (!session.sendUnpair()) { closeSession(); connect(); } }
            else { connected = false; closeSession(); connect(); }
            return START_STICKY;
        }
        if (ACTION_SEND_TEXT.equals(action) && intent != null) {
            String text = intent.getStringExtra(EXTRA_TEXT);
            if (text != null && OrbitalProtocol.isValidClipText(text)) pendingText = text;
            action = ACTION_START;
        }
        if (ACTION_STOP.equals(action)) { active = false; connectionReady = false; saveActive(false); closeSession(); stopForeground(true); publish("Orbital desactivado."); stopSelf(); return START_NOT_STICKY; }
        if (ACTION_PAUSE.equals(action)) { active = false; connectionReady = false; saveActive(false); closeSession(); stopForeground(true); publish("Orbital pausado."); stopSelf(); return START_NOT_STICKY; }
        if (intent == null && hasPendingRevocation() && !getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_ACTIVE, false)) {
            active = false; startForeground(NOTIFICATION_ID, notification("Quitando el vínculo en tu Mac por la red local…", false)); connect(); return START_STICKY;
        }
        active = true;
        connectionReady = connected && session != null;
        saveActive(true);
        startForeground(NOTIFICATION_ID, notification("Orbital activo · conectando con tu Mac", false));
        TileService.requestListeningState(this, new android.content.ComponentName(this, OrbitalTileService.class));
        // A share action can arrive while the persistent session is already
        // connected. connect() is then a no-op, so send through that session.
        if (pendingText != null && session != null && connected) {
            String outgoing = pendingText;
            if (session.sendText(outgoing)) {
                pendingText = null;
                publish("Enviando copia al Mac por Orbital…");
            }
        }
        connect();
        return START_STICKY;
    }

    private void connect() {
        if (!shouldRun() || !hasWifi() || session != null) return;
        OrbitalAndroidSession.PairedMac paired = loadPaired();
        if (paired == null) paired = loadPendingMac();
        if (paired == null) { publish("Empareja un Mac para activar Orbital."); return; }
        if (retry != null) { handler.removeCallbacks(retry); retry = null; }
        int myGeneration = ++generation;
        publish("Buscando el Mac emparejado en esta Wi‑Fi…");
        session = new OrbitalAndroidSession(this, new OrbitalAndroidSession.Listener() {
            @Override public void onStatus(String value) { if (myGeneration == generation) handleSessionStatus(value); }
            @Override public void onPairingComparisonCode(String code) {}
            @Override public void onPaired(OrbitalAndroidSession.PairedMac mac) {}
            @Override public void onClip(OrbitalAndroidSession.ReceivedClip clip) { if (myGeneration == generation) OrbitalService.this.onClip(clip); }
            @Override public void onUnpaired(UUID macId) { if (myGeneration == generation) handleRemoteUnpair(macId); }
            @Override public void onUnpairAcknowledged(UUID macId) { if (myGeneration == generation) finishPendingUnpair(macId); }
            @Override public void onClosed() { if (myGeneration == generation) handleSessionClosed(); }
        });
        session.reconnect(paired, deviceName());
    }

    private boolean hasWifi() {
        if (connectivity == null) return false;
        Network net = connectivity.getActiveNetwork();
        NetworkCapabilities caps = net == null ? null : connectivity.getNetworkCapabilities(net);
        return caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN);
    }
    private void handleSessionStatus(String value) {
        if (value.startsWith("El certificado seguro del Mac cambió")) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(KEY_REPAIR_REQUIRED, true).apply();
            active = false; connected = false; connectionReady = false; saveActive(false); closeSession();
            stopForeground(true); publish(value); stopSelf();
            return;
        }
        if (value.startsWith("El Mac ya no reconoce este teléfono")) {
            clearPairingState();
            active = false; connected = false; connectionReady = false; saveActive(false); closeSession();
            stopForeground(true);
            publish("Tu Mac quitó el vínculo con este teléfono.");
            stopSelf();
            return;
        }
        if (value.startsWith("Conectado al Mac")) {
            boolean wasConnected = connected; connected = true;
            connectionReady = true;
            if (hasPendingRevocation()) {
                publish("Quitando el vínculo en tu Mac…");
                if (session == null || !session.sendUnpair()) scheduleRetry();
                return;
            }
            publish("Orbital activo · conectado a tu Mac");
            if (!wasConnected) notifyReconnect("Conexión Orbital restablecida");
            if (pendingText != null && session != null && session.sendText(pendingText)) {
                pendingText = null;
                publish("Enviando copia al Mac por Orbital…");
            }
        } else if (value.startsWith("No se pudo") || value.startsWith("El servicio no apunta")) {
            connected = false; connectionReady = false; publish("Sin conexión · reintentando en esta Wi‑Fi"); scheduleRetry();
        } else publish(value);
    }
    private void handleSessionClosed() { session = null; if (shouldRun()) { connected = false; connectionReady = false; scheduleRetry(); } }
    private void scheduleRetry() {
        if (!shouldRun() || retry != null) return;
        retry = () -> { retry = null; connect(); };
        handler.postDelayed(retry, 5_000L);
    }
    private void closeSession() { generation++; if (retry != null) handler.removeCallbacks(retry); retry = null; OrbitalAndroidSession old = session; session = null; if (old != null) old.close(); }

    private boolean shouldRun() { return active || hasPendingRevocation(); }
    private boolean hasPendingRevocation() {
        SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
        return p.contains(KEY_PENDING_MAC_ID) && p.contains(KEY_PENDING_PIN);
    }
    private OrbitalAndroidSession.PairedMac loadPendingMac() {
        SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
        String id = p.getString(KEY_PENDING_MAC_ID, null), pin = p.getString(KEY_PENDING_PIN, null);
        if (id == null || pin == null || !pin.matches("[0-9a-f]{64}")) return null;
        try { byte[] fp = new byte[32]; for (int i=0;i<32;i++) fp[i]=(byte)Integer.parseInt(pin.substring(i*2,i*2+2),16); return new OrbitalAndroidSession.PairedMac(UUID.fromString(id), fp); }
        catch (IllegalArgumentException e) { return null; }
    }
    private boolean matchesPendingMac(UUID id) { OrbitalAndroidSession.PairedMac p = loadPendingMac(); return p != null && p.macId.equals(id); }
    private void clearPendingRevocation() { getSharedPreferences(PREFS, MODE_PRIVATE).edit().remove(KEY_PENDING_MAC_ID).remove(KEY_PENDING_PIN).apply(); }
    private void clearPairingState() { getSharedPreferences(PREFS, MODE_PRIVATE).edit().remove(KEY_MAC_ID).remove(KEY_PIN).remove(KEY_PENDING_MAC_ID).remove(KEY_PENDING_PIN).putBoolean(KEY_ACTIVE, false).apply(); }
    private void handleRemoteUnpair(UUID macId) {
        if (!matchesPendingMac(macId) && !matchesPairedMac(macId)) return;
        clearPairingState(); active = false; connected = false; connectionReady = false;
        closeSession(); stopForeground(true); publish("Tu Mac quitó el vínculo con este teléfono."); stopSelf();
    }
    private boolean matchesPairedMac(UUID id) { OrbitalAndroidSession.PairedMac p = loadPaired(); return p != null && p.macId.equals(id); }
    private void finishPendingUnpair(UUID macId) {
        if (!matchesPendingMac(macId)) return;
        clearPendingRevocation(); active = false; saveActive(false); connected = false; connectionReady = false;
        closeSession(); stopForeground(true); publish("Vínculo eliminado en ambos dispositivos."); stopSelf();
    }

    private void onClip(OrbitalAndroidSession.ReceivedClip clip) {
        ClipboardManager manager = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (manager != null) manager.setPrimaryClip(sensitiveTextClip("Paste Shifter · Orbital", clip.text));
        Intent event = new Intent(ACTION_CLIP).setPackage(getPackageName()).putExtra(EXTRA_TEXT, clip.text);
        sendBroadcast(event);
        notifyReceived();
        publish("Copia recibida desde el Mac y lista para pegar.");
    }

    private OrbitalAndroidSession.PairedMac loadPaired() {
        SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
        String id = p.getString(KEY_MAC_ID, null), pin = p.getString(KEY_PIN, null);
        if (id == null || pin == null || !pin.matches("[0-9a-f]{64}")) return null;
        try { byte[] fingerprint = new byte[32]; for (int i=0;i<32;i++) fingerprint[i]=(byte)Integer.parseInt(pin.substring(i*2,i*2+2),16); return new OrbitalAndroidSession.PairedMac(UUID.fromString(id), fingerprint); }
        catch (IllegalArgumentException e) { return null; }
    }
    private String deviceName() { String value = (Build.MANUFACTURER + " " + Build.MODEL).trim(); return value.length() > 64 ? value.substring(0,64) : value; }
    private void saveActive(boolean value) { getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(KEY_ACTIVE, value).apply(); }
    public static boolean isActive(Context context) { return context.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_ACTIVE, false); }
    public static boolean isConnected() { return connectionReady; }
    private void publish(String status) {
        Intent event = new Intent(ACTION_STATUS).setPackage(getPackageName()).putExtra(EXTRA_STATUS, status);
        sendBroadcast(event);
        if (shouldRun()) { NotificationManager nm = getSystemService(NotificationManager.class); if (nm != null) nm.notify(NOTIFICATION_ID, notification(status, connected)); }
        TileService.requestListeningState(this, new android.content.ComponentName(this, OrbitalTileService.class));
    }
    private Notification notification(String text, boolean isConnected) {
        Intent launch = new Intent(this, MainActivity.class);
        PendingIntent open = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Intent action = new Intent(this, OrbitalService.class).setAction(active ? ACTION_PAUSE : ACTION_RESUME);
        PendingIntent toggle = PendingIntent.getService(this, 1, action, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = new Notification.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentTitle("Paste Shifter · Orbital").setContentText(text).setContentIntent(open)
                .setOngoing(active || hasPendingRevocation()).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE);
        if (active) builder.addAction(new Notification.Action.Builder(0, "Pausar", toggle).build());
        return builder.build();
    }
    private void notifyReconnect(String text) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(NOTIFICATION_ID + 1, new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_menu_share).setContentTitle("Paste Shifter")
                .setContentText(text).setAutoCancel(true).build());
    }
    private void notifyReceived() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null || !nm.areNotificationsEnabled()) return;
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) return;
        Intent launch = new Intent(this, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent open = PendingIntent.getActivity(this, 2, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = new Notification.Builder(this, RECEIVE_CHANNEL)
                .setSmallIcon(android.R.drawable.stat_notify_chat)
                .setContentTitle("Texto del Mac listo para pegar")
                .setContentText("Ya está en el portapapeles de este teléfono.")
                .setContentIntent(open)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setVisibility(Notification.VISIBILITY_PRIVATE);
        nm.notify(RECEIVE_NOTIFICATION_ID, builder.build());
    }
    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL, "Orbital", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Estado de la conexión local de Paste Shifter");
            NotificationChannel received = new NotificationChannel(RECEIVE_CHANNEL, "Copias recibidas", NotificationManager.IMPORTANCE_DEFAULT);
            received.setDescription("Aviso y sonido cuando llega texto desde tu Mac por Orbital");
            received.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
            NotificationManager nm = getSystemService(NotificationManager.class);
            nm.createNotificationChannel(channel);
            nm.createNotificationChannel(received);
        }
    }
    @Override public void onDestroy() { active = false; connectionReady = false; closeSession(); if (clipboardReceiverRegistered) try { unregisterReceiver(clipboardReceiver); } catch (RuntimeException ignored) {} if (connectivity != null && networkCallback != null) try { connectivity.unregisterNetworkCallback(networkCallback); } catch (RuntimeException ignored) {} super.onDestroy(); }
    @Override public IBinder onBind(Intent intent) { return null; }
}
