package cl.pasteshifter.orbital;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import java.net.InetAddress;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/** Finds only the Bonjour service whose instance name matches the QR Mac UUID. */
@SuppressWarnings("deprecation")
public final class OrbitalDiscovery {
    public interface Callback {
        void onFound(InetAddress address, int port);
        void onFailure(String reason);
    }

    private static final String SERVICE_TYPE = "_orbital._tcp.";
    private final Context context;
    private final NsdManager manager;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AtomicBoolean resolving = new AtomicBoolean(false);
    private NsdManager.DiscoveryListener listener;
    private Callback callback;
    private UUID expectedMacId;
    private Runnable discoveryTimeout;
    private WifiManager.MulticastLock multicastLock;

    public OrbitalDiscovery(Context context) {
        this.context = context.getApplicationContext();
        manager = (NsdManager) this.context.getSystemService(Context.NSD_SERVICE);
    }

    public synchronized void start(UUID macId, Callback callback) {
        stop();
        if (manager == null) {
            callback.onFailure("Android no ofrece descubrimiento mDNS en este momento");
            return;
        }
        this.expectedMacId = macId;
        this.callback = callback;
        this.resolving.set(false);
        listener = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String serviceType) {}

            @Override public void onServiceFound(NsdServiceInfo serviceInfo) {
                if (expectedMacId == null || !expectedMacId.toString().equalsIgnoreCase(serviceInfo.getServiceName())
                        || !resolving.compareAndSet(false, true)) return;
                try {
                    manager.resolveService(serviceInfo, new NsdManager.ResolveListener() {
                        @Override public void onResolveFailed(NsdServiceInfo service, int errorCode) {
                            resolving.set(false);
                        }

                        @Override public void onServiceResolved(NsdServiceInfo service) {
                            Callback target;
                            synchronized (OrbitalDiscovery.this) {
                                target = OrbitalDiscovery.this.callback;
                                stop();
                            }
                            if (target != null && service.getHost() != null && service.getPort() > 0) {
                                target.onFound(service.getHost(), service.getPort());
                            } else if (target != null) {
                                target.onFailure("El Mac anunció una dirección local inválida");
                            }
                        }
                    });
                } catch (RuntimeException e) {
                    resolving.set(false);
                    fail("No se pudo resolver el servicio local");
                }
            }

            @Override public void onServiceLost(NsdServiceInfo serviceInfo) {}
            @Override public void onDiscoveryStopped(String serviceType) {}
            @Override public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                fail("No se pudo iniciar el descubrimiento local (" + errorCode + ")");
            }
            @Override public void onStopDiscoveryFailed(String serviceType, int errorCode) {}
        };
        try {
            // Android 10–12 need an explicit multicast lock for foreground mDNS.
            if (Build.VERSION.SDK_INT < 33) {
                WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
                if (wifi == null) throw new IllegalStateException("Wi‑Fi service unavailable");
                multicastLock = wifi.createMulticastLock("PasteShifter-Orbital-mDNS");
                multicastLock.setReferenceCounted(false);
                multicastLock.acquire();
            }
            discoveryTimeout = () -> fail("No se encontró el Mac en esta red Wi‑Fi.");
            handler.postDelayed(discoveryTimeout, 20_000L);
            manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener);
        } catch (RuntimeException e) {
            fail("Android rechazó el descubrimiento local");
        }
    }

    public synchronized void stop() {
        if (discoveryTimeout != null) handler.removeCallbacks(discoveryTimeout);
        discoveryTimeout = null;
        if (listener != null && manager != null) {
            try { manager.stopServiceDiscovery(listener); } catch (RuntimeException ignored) {}
        }
        if (multicastLock != null && multicastLock.isHeld()) multicastLock.release();
        multicastLock = null;
        listener = null;
        expectedMacId = null;
        callback = null;
        resolving.set(false);
    }

    private void fail(String reason) {
        Callback target;
        synchronized (this) {
            target = callback;
            stop();
        }
        if (target != null) target.onFailure(reason);
    }

}
