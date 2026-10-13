package cl.pasteshifter.orbital;

import android.app.Activity;
import android.content.ClipData;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.view.View;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.FrameLayout;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.UUID;

/** Companion UI for explicit sends and locally received Orbital clipboard text. */
public final class MainActivity extends Activity implements OrbitalAndroidSession.Listener {
    private static final int REQUEST_SCAN_QR = 4201;
    private static final int REQUEST_LOCAL_NETWORK = 4202;
    private static final String DEVICE_PREFS = "orbital-device.v1";
    private static final String KEY_MAC_ID = "paired_mac_id";
    private static final String KEY_PIN = "paired_mac_pin";
    private static final String KEY_REPAIR_REQUIRED = "paired_mac_repair_required";

    private final ArrayDeque<OrbitalAndroidSession.ReceivedClip> history = new ArrayDeque<>();
    private final LinkedHashSet<UUID> receivedIds = new LinkedHashSet<>();
    private final LinkedHashSet<String> recentIncomingText = new LinkedHashSet<>();
    private OrbitalAndroidSession session;
    private OrbitalAndroidSession.PairedMac pairedMac;
    private SharedPreferences preferences;
    private ClipboardManager clipboard;
    private TextView statusView;
    private TextView deviceView;
    private TextView connectionBadge;
    private OrbitalRingsView orbitalRings;
    private LinearLayout historyRows;
    private TextView historyEmptyView;
    private Button connectionToggle;
    private EditText macComposer;
    private View shareCard;
    private View shareLockedCard;
    private FrameLayout screenContainer;
    private View optionsOverlay;
    private BroadcastReceiver orbitalReceiver;
    private String lastObservedClipboard;
    private String deviceName;
    private Runnable localNetworkPermissionContinuation;
    private boolean needsRepairPairing;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        preferences = getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE);
        clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        deviceName = makeDeviceName();
        pairedMac = loadPairedMac();
        needsRepairPairing = preferences.getBoolean(KEY_REPAIR_REQUIRED, false);
        // Repair the stale state left by earlier builds, which could forget
        // the Mac in the screen while leaving the background service active.
        if (pairedMac == null && OrbitalService.isActive(this)) OrbitalService.forgetPairing(this);
        buildInterface();
        renderPairedState();
        OrbitalService.resumePendingRevocation(this);
        if (OrbitalService.isActive(this) && pairedMac != null) OrbitalService.start(this);
        OrbitalShareTarget.refresh(this, pairedMac != null);
    }

    @Override protected void onResume() {
        super.onResume();
        registerOrbitalReceiver();
        updateConnectionButton();
        OrbitalShareTarget.refresh(this, pairedMac != null);
    }

    @Override protected void onPause() {
        unregisterOrbitalReceiver();
        closeSession(null);
        super.onPause();
    }

    @Override protected void onDestroy() {
        closeSession(null);
        super.onDestroy();
    }

    private void buildInterface() {
        getWindow().setStatusBarColor(0xff111019);
        getWindow().setNavigationBarColor(0xff111019);
        if (Build.VERSION.SDK_INT >= 26) {
            getWindow().getDecorView().setSystemUiVisibility(0);
        }

        ScrollView scroll = new ScrollView(this);
        scroll.setVerticalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(22), dp(18), dp(22), dp(30));
        android.graphics.drawable.GradientDrawable backdrop = new android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                new int[]{0xff111019, 0xff171420, 0xff11151d});
        root.setBackground(backdrop);
        scroll.addView(root);

        LinearLayout brand = new LinearLayout(this);
        brand.setGravity(Gravity.CENTER_VERTICAL);
        brand.addView(new OrbitalMarkView(this), new LinearLayout.LayoutParams(dp(52), dp(52)));
        LinearLayout brandText = new LinearLayout(this);
        brandText.setOrientation(LinearLayout.VERTICAL);
        brandText.setPadding(dp(12), 0, 0, 0);
        TextView title = heading("Paste Shifter"); title.setTextSize(22); brandText.addView(title);
        TextView subtitle = secondary("ORBITAL  ·  CONEXIÓN LOCAL SEGURA");
        subtitle.setTextSize(11); brandText.addView(subtitle);
        brand.addView(brandText, params(-1,-2)); root.addView(brand);

        LinearLayout hero = new LinearLayout(this);
        hero.setGravity(Gravity.CENTER_HORIZONTAL);
        hero.setOrientation(LinearLayout.VERTICAL);
        hero.setPadding(dp(20), dp(19), dp(20), dp(20));
        hero.setBackground(panelBackground(true));
        LinearLayout.LayoutParams heroParams = params(-1, -2); heroParams.topMargin = dp(23); root.addView(hero, heroParams);

        TextView overline = accentLabel("CONEXIÓN ORBITAL");
        hero.addView(overline);
        android.widget.FrameLayout core = new android.widget.FrameLayout(this);
        orbitalRings = new OrbitalRingsView(this);
        core.addView(orbitalRings, new android.widget.FrameLayout.LayoutParams(-1, -1));
        connectionBadge = new TextView(this);
        connectionBadge.setGravity(Gravity.CENTER);
        connectionBadge.setTextSize(42);
        connectionBadge.setTypeface(null, android.graphics.Typeface.BOLD);
        connectionBadge.setTextColor(0xffffffff);
        connectionBadge.setElevation(dp(8));
        android.widget.FrameLayout.LayoutParams badgeParams = new android.widget.FrameLayout.LayoutParams(dp(88), dp(88), Gravity.CENTER);
        core.addView(connectionBadge, badgeParams);
        LinearLayout.LayoutParams coreParams = params(dp(132), dp(132)); coreParams.topMargin = dp(8);
        hero.addView(core, coreParams);

        statusView = heading("Conecta tu Mac");
        statusView.setGravity(Gravity.CENTER); statusView.setTextSize(22);
        LinearLayout.LayoutParams statusParams = params(-1, -2); statusParams.topMargin = dp(16); hero.addView(statusView, statusParams);
        deviceView = secondary(""); deviceView.setGravity(Gravity.CENTER); deviceView.setTextSize(13);
        deviceView.setLineSpacing(dp(2), 1f);
        LinearLayout.LayoutParams deviceParams = params(-1, -2); deviceParams.topMargin = dp(7); hero.addView(deviceView, deviceParams);

        connectionToggle = new Button(this);
        styleButton(connectionToggle, true); connectionToggle.setOnClickListener(v -> toggleConnection());
        LinearLayout.LayoutParams toggleParams = params(-1, -2); toggleParams.topMargin = dp(20); hero.addView(connectionToggle, toggleParams);
        TextView transportHint = secondary("MAC  ↔  ANDROID     ·     SOLO TU RED WI‑FI");
        transportHint.setGravity(Gravity.CENTER); transportHint.setTextSize(10); transportHint.setLetterSpacing(.04f);
        LinearLayout.LayoutParams hintParams = params(-1,-2); hintParams.topMargin = dp(13); hero.addView(transportHint,hintParams);

        LinearLayout shareCard = new LinearLayout(this);
        this.shareCard = shareCard;
        shareCard.setOrientation(LinearLayout.VERTICAL);
        shareCard.setPadding(dp(17), dp(15), dp(17), dp(15));
        shareCard.setBackground(panelBackground(false));
        LinearLayout.LayoutParams shareCardParams = params(-1,-2); shareCardParams.topMargin = dp(14);
        root.addView(shareCard, shareCardParams);
        TextView shareTitle = heading("Enviar texto al Mac"); shareTitle.setTextSize(16); shareCard.addView(shareTitle);
        TextView how = secondary("Escribe o pega aquí. También puedes seleccionar texto en otra app y usar Compartir → Paste Shifter · Mi Mac.");
        how.setTextSize(12); how.setLineSpacing(dp(3), 1f);
        LinearLayout.LayoutParams howParams=params(-1,-2); howParams.topMargin=dp(7); shareCard.addView(how,howParams);
        macComposer = new EditText(this);
        macComposer.setTextColor(0xfff4f0fa);
        macComposer.setHintTextColor(0xff958da3);
        macComposer.setHint("Escribe o pega el texto aquí");
        macComposer.setTextSize(14);
        macComposer.setGravity(Gravity.TOP | Gravity.START);
        macComposer.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        macComposer.setMinLines(2);
        macComposer.setMaxLines(5);
        macComposer.setPadding(dp(12), dp(10), dp(12), dp(10));
        android.graphics.drawable.GradientDrawable composerBackground = new android.graphics.drawable.GradientDrawable();
        composerBackground.setColor(0xff17151f);
        composerBackground.setCornerRadius(dp(13));
        composerBackground.setStroke(dp(1), 0xff42394e);
        macComposer.setBackground(composerBackground);
        LinearLayout.LayoutParams composerParams=params(-1,-2); composerParams.topMargin=dp(11); shareCard.addView(macComposer,composerParams);

        Button sendToMac = new Button(this);
        sendToMac.setText("Enviar al Mac");
        styleButton(sendToMac, true);
        sendToMac.setOnClickListener(v -> {
            if (pairedMac == null) {
                renderPairedState();
                Toast.makeText(this, "Conecta un Mac para enviar texto.", Toast.LENGTH_SHORT).show();
                return;
            }
            String text = macComposer.getText().toString();
            if (text.trim().isEmpty() || !OrbitalProtocol.isValidClipText(text)) {
                Toast.makeText(this, "Escribe un texto para enviar.", Toast.LENGTH_SHORT).show();
                return;
            }
            OrbitalService.sendText(this, text);
            macComposer.setText("");
            statusView.setText("Enviando texto a tu Mac…");
        });
        LinearLayout.LayoutParams sendParams=params(-1,-2); sendParams.topMargin=dp(8); shareCard.addView(sendToMac,sendParams);
        TextView pasteHint = secondary("En el Mac quedará listo para ⌘V y en el historial Orbital.");
        pasteHint.setTextSize(11); pasteHint.setTextColor(0xffd2a9ff);
        LinearLayout.LayoutParams pasteHintParams=params(-1,-2); pasteHintParams.topMargin=dp(7); shareCard.addView(pasteHint,pasteHintParams);

        LinearLayout locked = new LinearLayout(this);
        shareLockedCard = locked;
        locked.setOrientation(LinearLayout.VERTICAL);
        locked.setPadding(dp(17), dp(16), dp(17), dp(16));
        locked.setBackground(panelBackground(false));
        LinearLayout.LayoutParams lockedParams=params(-1,-2); lockedParams.topMargin=dp(14); root.addView(locked,lockedParams);
        TextView lockedTitle=heading("Envía texto a tu Mac"); lockedTitle.setTextSize(16); locked.addView(lockedTitle);
        TextView lockedInfo=secondary("Conecta tu Mac una vez y podrás enviar texto desde aquí o desde cualquier app.");
        lockedInfo.setTextSize(12); lockedInfo.setLineSpacing(dp(3),1f);
        LinearLayout.LayoutParams lockedInfoParams=params(-1,-2); lockedInfoParams.topMargin=dp(7); locked.addView(lockedInfo,lockedInfoParams);
        Button lockedPair=new Button(this); lockedPair.setText("Conectar un Mac"); styleButton(lockedPair,false);
        lockedPair.setOnClickListener(v->startQrScan());
        LinearLayout.LayoutParams lockedButtonParams=params(-1,-2); lockedButtonParams.topMargin=dp(10); locked.addView(lockedPair,lockedButtonParams);

        Button more = new Button(this); more.setText("Más opciones"); styleButton(more, false);
        more.setOnClickListener(v -> showMoreOptions());
        LinearLayout.LayoutParams moreParams=params(-1,-2); moreParams.topMargin=dp(11); root.addView(more,moreParams);

        TextView receiveHeading = heading("Copias recientes"); receiveHeading.setTextSize(17);
        LinearLayout.LayoutParams headingParams=params(-1,-2); headingParams.topMargin=dp(27); root.addView(receiveHeading,headingParams);
        historyEmptyView = secondary("Al enviar desde el Mac, el texto queda en el portapapeles, listo para pegar en cualquier app.");
        historyEmptyView.setTextSize(12);
        LinearLayout.LayoutParams emptyParams=params(-1,-2); emptyParams.topMargin=dp(6); root.addView(historyEmptyView,emptyParams);
        historyRows=new LinearLayout(this); historyRows.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams rowsParams=params(-1,-2); rowsParams.topMargin=dp(8); root.addView(historyRows,rowsParams);

        screenContainer = new FrameLayout(this);
        screenContainer.addView(scroll, new FrameLayout.LayoutParams(-1,-1));
        setContentView(screenContainer);
        updateConnectionButton();
        root.setAlpha(0f); root.setTranslationY(dp(12));
        root.animate().alpha(1f).translationY(0f).setDuration(420)
                .setInterpolator(new android.view.animation.DecelerateInterpolator()).start();
    }

    private android.graphics.drawable.Drawable panelBackground(boolean hero) {
        android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                hero ? new int[]{0xff28243a, 0xff1a1a27, 0xff191e29}
                        : new int[]{0xff211e2d, 0xff1a1925});
        bg.setCornerRadius(dp(hero ? 28 : 20));
        bg.setStroke(dp(1), hero ? 0xff48405d : 0xff363143);
        return bg;
    }

    private TextView secondary(String value) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextColor(0xffb8b2c7); view.setTextSize(13);
        return view;
    }

    private TextView accentLabel(String value) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextColor(0xffd4a9ff); view.setTextSize(10);
        view.setTypeface(null, android.graphics.Typeface.BOLD); view.setLetterSpacing(.14f);
        return view;
    }

    private void showMoreOptions() {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        if (pairedMac != null) {
            addSheetAction(content, "Conectar otro Mac", "Vincula un segundo dispositivo", "＋", this::startQrScan);
            addSheetAction(content, "Olvidar este Mac", "Eliminar el vínculo en ambos dispositivos", "⌫", this::showForgetConfirmation);
        } else {
            addSheetAction(content, "Conectar un Mac", "Escanea el código de Paste Shifter", "◉", this::startQrScan);
        }
        addSheetAction(content, "Acceso rápido", "Añade Orbital al panel de Ajustes rápidos", "✦", this::addQuickSettingsTile);
        showSheet("Más opciones", "Ajusta cómo usas Orbital", content, "Listo", null);
    }

    private void addSheetAction(LinearLayout parent, String title, String detail, String icon, Runnable action) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL); row.setPadding(dp(13),dp(12),dp(13),dp(12));
        row.setBackground(panelBackground(false));
        TextView symbol=heading(icon); symbol.setTextSize(20); symbol.setGravity(Gravity.CENTER);
        row.addView(symbol,new LinearLayout.LayoutParams(dp(38),dp(38)));
        LinearLayout labels=new LinearLayout(this); labels.setOrientation(LinearLayout.VERTICAL); labels.setPadding(dp(10),0,0,0);
        TextView label=heading(title); label.setTextSize(14); labels.addView(label);
        TextView caption=secondary(detail); caption.setTextSize(11); labels.addView(caption);
        row.addView(labels,new LinearLayout.LayoutParams(0,-2,1));
        TextView arrow=secondary("›"); arrow.setTextSize(24); row.addView(arrow);
        row.setOnClickListener(v->{ hideSheet(); action.run(); });
        LinearLayout.LayoutParams p=params(-1,-2); p.topMargin=dp(8); parent.addView(row,p);
    }

    private void showSheet(String title, String subtitle, View content, String closeLabel, Runnable closeAction) {
        hideSheet();
        View dim=new View(this); dim.setBackgroundColor(0xaa08070d); dim.setAlpha(0f);
        FrameLayout.LayoutParams dimParams=new FrameLayout.LayoutParams(-1,-1); screenContainer.addView(dim,dimParams);
        LinearLayout sheet=new LinearLayout(this); sheet.setOrientation(LinearLayout.VERTICAL);
        sheet.setPadding(dp(20),dp(18),dp(20),dp(22)); sheet.setBackground(panelBackground(true));
        FrameLayout.LayoutParams sheetParams=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);
        sheetParams.setMargins(dp(10),0,dp(10),dp(10)); screenContainer.addView(sheet,sheetParams);
        TextView heading=heading(title); heading.setTextSize(20); sheet.addView(heading);
        TextView hint=secondary(subtitle); hint.setTextSize(12);
        LinearLayout.LayoutParams hintParams=params(-1,-2); hintParams.topMargin=dp(4); sheet.addView(hint,hintParams);
        sheet.addView(content);
        Button close=new Button(this); close.setText(closeLabel); styleButton(close,false);
        close.setOnClickListener(v->{hideSheet();if(closeAction!=null)closeAction.run();});
        LinearLayout.LayoutParams closeParams=params(-1,-2); closeParams.topMargin=dp(12); sheet.addView(close,closeParams);
        dim.setOnClickListener(v->hideSheet());
        optionsOverlay=dim;
        sheet.setTranslationY(dp(40)); sheet.setAlpha(0f); dim.animate().alpha(1f).setDuration(180).start();
        sheet.animate().translationY(0).alpha(1f).setDuration(240).setInterpolator(new android.view.animation.DecelerateInterpolator()).start();
    }

    private void hideSheet() {
        if(optionsOverlay!=null) { View dim=optionsOverlay; optionsOverlay=null; screenContainer.removeView(dim); }
        if(screenContainer!=null) {
            for(int i=screenContainer.getChildCount()-1;i>=1;i--) screenContainer.removeViewAt(i);
        }
    }

    private void showForgetConfirmation() {
        LinearLayout content=new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL);
        TextView message=secondary("Se quitará el vínculo de este teléfono y del Mac. Si ahora no están conectados, el cambio se completará cuando vuelvan a encontrarse.");
        message.setTextSize(13); message.setLineSpacing(dp(3),1f); content.addView(message);
        Button forget=new Button(this); forget.setText("Olvidar Mac"); styleButton(forget,false);
        forget.setOnClickListener(v->{hideSheet();forgetPairedMac();});
        LinearLayout.LayoutParams p=params(-1,-2);p.topMargin=dp(12);content.addView(forget,p);
        showSheet("¿Olvidar este Mac?","El vínculo se eliminará en ambos dispositivos",content,"Cancelar",null);
    }

    private void forgetPairedMac() {
        if(pairedMac==null)return;
        closeSession(null); pairedMac=null; OrbitalService.forgetPairing(this); renderPairedState();
    }

    private void toggleConnection() {
        if (needsRepairPairing) { startQrScan(); return; }
        if (pairedMac == null) { startQrScan(); return; }
        if (OrbitalService.isActive(this)) {
            OrbitalService.pause(this); statusView.setText("Orbital está en pausa");
        } else {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 4203);
            }
            withLocalNetworkPermission(() -> { OrbitalService.start(this); statusView.setText("Conectando con tu Mac…"); });
        }
        updateConnectionButton();
    }

    private void addQuickSettingsTile() {
        if (Build.VERSION.SDK_INT >= 33) {
            android.app.StatusBarManager statusBar = getSystemService(android.app.StatusBarManager.class);
            if (statusBar != null) statusBar.requestAddTileService(
                    new android.content.ComponentName(this, OrbitalTileService.class), "Orbital",
                    android.graphics.drawable.Icon.createWithResource(this, cl.pasteshifter.orbital.R.mipmap.ic_launcher),
                    getMainExecutor(), result -> {
                        if (result == android.app.StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED
                                || result == android.app.StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED)
                            Toast.makeText(this, "Control Orbital añadido.", Toast.LENGTH_SHORT).show();
                    });
        } else {
            Toast.makeText(this, "Edita los Ajustes rápidos y añade el control de Paste Shifter.", Toast.LENGTH_LONG).show();
        }
    }

    private void updateConnectionButton() {
        boolean active = OrbitalService.isActive(this);
        if (connectionToggle != null) {
            connectionToggle.setText(needsRepairPairing ? "Vincular de nuevo" : (active ? "Pausar conexión" : (pairedMac == null ? "Emparejar con un Mac" : "Conectar con mi Mac")));
            styleButton(connectionToggle, needsRepairPairing || active || pairedMac == null);
        }
        if (connectionBadge != null) {
            boolean ready = OrbitalService.isConnected();
            if (orbitalRings != null) orbitalRings.setConnected(ready);
            boolean wasReady = "✓".contentEquals(connectionBadge.getText());
            connectionBadge.setText(ready ? "✓" : (pairedMac == null ? "✦" : "···"));
            connectionBadge.setTextColor(0xffffffff);
            android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable(
                    android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                    ready ? new int[]{0xff55d6b0,0xff238d79}
                            : new int[]{0xff413457,0xff292535});
            bg.setShape(android.graphics.drawable.GradientDrawable.OVAL);
            bg.setStroke(dp(1), ready ? 0xff8ff2d3 : 0xff7d68a0);
            connectionBadge.setBackground(bg);
            if (wasReady != ready) {
                connectionBadge.setScaleX(0.82f); connectionBadge.setScaleY(0.82f); connectionBadge.setAlpha(0.6f);
                connectionBadge.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(260).start();
            }
        }
        if (statusView != null && deviceView != null) {
            boolean ready = OrbitalService.isConnected();
            if (ready) {
                statusView.setText("Todo listo");
                deviceView.setText("Conectado a tu Mac. Comparte texto con Paste Shifter para pegarlo allí.");
            } else if (needsRepairPairing) {
                statusView.setText("Actualiza el vínculo seguro");
                deviceView.setText("Escanea otra vez el código de tu Mac para confirmar su identidad.");
            } else if (active) {
                statusView.setText("Buscando tu Mac…");
                deviceView.setText("Paste Shifter volverá a conectar al encontrarlo en esta Wi‑Fi.");
            } else if (pairedMac != null) {
                statusView.setText("Orbital está en pausa");
                deviceView.setText("Tu Mac sigue vinculado. Reanuda la conexión cuando quieras.");
            } else {
                statusView.setText("Conecta tu Mac");
                deviceView.setText("Escanea el código que aparece en Paste Shifter para Mac.");
            }
        }
    }
    private void styleButton(Button button, boolean prominent) {
        int[] colors = prominent ? new int[]{0xffa244ec,0xff702bc0} : new int[]{0xff302b3b,0xff262431};
        android.graphics.drawable.GradientDrawable background = new android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.LEFT_RIGHT, colors);
        background.setCornerRadius(dp(15));
        background.setStroke(dp(1), prominent ? 0xffc175fb : 0xff464052);
        button.setBackground(background);
        button.setTextColor(prominent ? 0xffffffff : 0xffe4deed);
        button.setAllCaps(false);
        button.setTextSize(14);
        button.setMinHeight(dp(52));
        button.setElevation(dp(prominent ? 5 : 1));
        button.setPadding(dp(13), dp(9), dp(13), dp(9));
        button.setOnTouchListener((view, event) -> {
            if (event.getAction() == android.view.MotionEvent.ACTION_DOWN) view.animate().scaleX(.985f).scaleY(.985f).setDuration(80).start();
            else if (event.getAction() == android.view.MotionEvent.ACTION_UP || event.getAction() == android.view.MotionEvent.ACTION_CANCEL)
                view.animate().scaleX(1f).scaleY(1f).setDuration(120).start();
            return false;
        });
    }

    private void registerOrbitalReceiver() {
        if (orbitalReceiver != null) return;
        orbitalReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                if (OrbitalService.ACTION_STATUS.equals(intent.getAction())) {
                    String value=intent.getStringExtra(OrbitalService.EXTRA_STATUS);
                    if(value!=null) showFriendlyStatus(value);
                } else if (OrbitalService.ACTION_CLIP.equals(intent.getAction())) {
                    statusView.setText("Copia recibida desde el Mac y puesta en el portapapeles.");
                }
                updateConnectionButton();
            }
        };
        IntentFilter filter=new IntentFilter(); filter.addAction(OrbitalService.ACTION_STATUS); filter.addAction(OrbitalService.ACTION_CLIP);
        if(Build.VERSION.SDK_INT>=33) registerReceiver(orbitalReceiver,filter,Context.RECEIVER_NOT_EXPORTED); else registerReceiver(orbitalReceiver,filter);
    }
    private void unregisterOrbitalReceiver() { if(orbitalReceiver!=null){ unregisterReceiver(orbitalReceiver); orbitalReceiver=null; } }

    private void showFriendlyStatus(String value) {
        if (value.startsWith("El Mac ya no reconoce este teléfono") || value.startsWith("Tu Mac quitó el vínculo")
                || value.startsWith("Vínculo eliminado en ambos dispositivos")) {
            pairedMac = null;
            preferences.edit().remove(KEY_MAC_ID).remove(KEY_PIN).apply();
            deviceView.setText("Vuelve a vincular tu Mac para continuar");
            statusView.setText("Vincula de nuevo tu Mac");
            renderPairedState();
        } else if (value.startsWith("Conectado al Mac") || value.contains("conectado a tu Mac")) {
            needsRepairPairing=false;
            preferences.edit().remove(KEY_REPAIR_REQUIRED).apply();
            statusView.setText("Todo listo");
            deviceView.setText("Conectado a tu Mac. Comparte texto con Paste Shifter para pegarlo allí.");
        } else if (value.startsWith("El certificado seguro del Mac cambió")) {
            needsRepairPairing=true;
            preferences.edit().putBoolean(KEY_REPAIR_REQUIRED,true).apply();
            updateConnectionButton();
        } else if (value.contains("reintentando") || value.contains("Buscando") || value.contains("Activando")) {
            statusView.setText("Buscando tu Mac…");
        } else if (value.contains("Wi‑Fi") || value.contains("Wi-Fi")) {
            statusView.setText("Esperando a que ambos estén en la misma red");
        } else if (value.contains("pausado")) {
            statusView.setText("Orbital está en pausa");
        } else if (value.contains("Copia recibida")) {
            statusView.setText("Copia lista para pegar");
        } else if (value.contains("Copia enviada")) {
            statusView.setText("Copia enviada al Mac");
        } else if (value.contains("Enviando copia")) {
            statusView.setText("Enviando texto a tu Mac…");
        } else if (value.contains("No se pudo")) {
            statusView.setText("No se pudo conectar · inténtalo de nuevo");
        } else statusView.setText(value);
    }

    private void startQrScan() {
        Intent intent = new Intent(this, QrScannerActivity.class);
        startActivityForResult(intent, REQUEST_SCAN_QR);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_SCAN_QR && resultCode == RESULT_OK && data != null) {
            String qr = data.getStringExtra(QrScannerActivity.EXTRA_QR);
            if (qr != null) pairFromQr(qr);
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_LOCAL_NETWORK) {
            Runnable continuation = localNetworkPermissionContinuation;
            localNetworkPermissionContinuation = null;
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED && continuation != null) {
                continuation.run();
            } else {
                statusView.setText("El permiso de red local es necesario para conectar con tu Mac.");
            }
        }
    }

    private void pairFromQr(String qr) {
        needsRepairPairing=false;
        preferences.edit().remove(KEY_REPAIR_REQUIRED).apply();
        updateConnectionButton();
        withLocalNetworkPermission(() -> {
            closeSession(null);
            session = newSession();
            statusView.setText("Conectando con tu Mac…");
            deviceView.setText("Estamos comprobando el código de forma segura.");
            session.pairFromQr(qr, deviceName);
        });
    }

    private void connectToPairedMac() {
        if (pairedMac == null) {
            statusView.setText("Añade un Mac para empezar.");
            return;
        }
        OrbitalService.start(this);
        statusView.setText("Activando Orbital en segundo plano…");
        updateConnectionButton();
        return;
    }

    private void withLocalNetworkPermission(Runnable continuation) {
        if (Build.VERSION.SDK_INT < 37 || getApplicationInfo().targetSdkVersion < 37
                || checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") == PackageManager.PERMISSION_GRANTED) {
            continuation.run();
            return;
        }
        localNetworkPermissionContinuation = continuation;
        LinearLayout content=new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL);
        TextView explanation=secondary("Paste Shifter usa tu Wi‑Fi para encontrar y conectar directamente con el Mac que vinculaste. El contenido no pasa por servidores externos.");
        explanation.setTextSize(13); explanation.setLineSpacing(dp(3),1f); content.addView(explanation);
        Button allow=new Button(this); allow.setText("Continuar"); styleButton(allow,true);
        allow.setOnClickListener(v->{hideSheet();requestPermissions(new String[]{"android.permission.ACCESS_LOCAL_NETWORK"},REQUEST_LOCAL_NETWORK);});
        LinearLayout.LayoutParams p=params(-1,-2);p.topMargin=dp(12);content.addView(allow,p);
        showSheet("Conexión en tu Wi‑Fi","Necesitamos permiso para encontrar tu Mac",content,"Ahora no",()->{
            localNetworkPermissionContinuation=null; statusView.setText("Conexión local pausada hasta que otorgues el permiso.");
        });
    }

    private OrbitalAndroidSession newSession() { return new OrbitalAndroidSession(this, this); }

    private void confirmForgetMac() {
        showForgetConfirmation();
    }

    private OrbitalAndroidSession.PairedMac loadPairedMac() {
        String id = preferences.getString(KEY_MAC_ID, null);
        String pin = preferences.getString(KEY_PIN, null);
        if (id == null || pin == null || !pin.matches("[0-9a-f]{64}")) return null;
        try { return new OrbitalAndroidSession.PairedMac(UUID.fromString(id), decodeHex(pin)); }
        catch (IllegalArgumentException error) { return null; }
    }

    private void renderPairedState() {
        boolean paired=pairedMac!=null;
        if(shareCard!=null) shareCard.setVisibility(paired?View.VISIBLE:View.GONE);
        if(shareLockedCard!=null) shareLockedCard.setVisibility(paired?View.GONE:View.VISIBLE);
        updateConnectionButton();
        OrbitalShareTarget.refresh(this, pairedMac != null);
    }

    private void closeSession(String finalStatus) {
        if (session != null) {
            session.close();
            session = null;
        }
        if (finalStatus != null && statusView != null) statusView.setText(finalStatus);
    }

    private static String makeDeviceName() {
        String manufacturer = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.trim();
        String model = Build.MODEL == null ? "Android" : Build.MODEL.trim();
        String name = (manufacturer + " " + model).trim();
        if (name.isEmpty()) name = "Android";
        int end = name.offsetByCodePoints(0, Math.min(64, name.codePointCount(0, name.length())));
        return name.substring(0, end);
    }

    private static byte[] decodeHex(String value) {
        byte[] bytes = new byte[value.length() / 2];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16);
        return bytes;
    }

    private static String encodeHex(byte[] bytes) {
        StringBuilder value = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) value.append(String.format(Locale.ROOT, "%02x", b & 0xff));
        return value.toString();
    }

    private void addReceivedClip(OrbitalAndroidSession.ReceivedClip clip) {
        if (!receivedIds.add(clip.clipId)) return;
        if (historyEmptyView != null) historyEmptyView.setVisibility(View.GONE);
        if (history.size() >= 60) {
            OrbitalAndroidSession.ReceivedClip old = history.removeLast();
            receivedIds.remove(old.clipId);
        }
        history.addFirst(clip);
        rememberIncomingText(clip.text);
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        card.setBackground(panelBackground(false));
        LinearLayout.LayoutParams cardParams = params(-1, -2);
        cardParams.topMargin = dp(8);
        historyRows.addView(card, 0, cardParams);

        TextView source = new TextView(this);
        source.setText("Orbital · " + clip.macName);
        source.setTextColor(0xffc7b7dc);
        source.setTextSize(11);
        card.addView(source);

        TextView content = new TextView(this);
        content.setText(clip.text);
        content.setTextColor(0xfff4f0fa);
        content.setTextSize(14);
        content.setMaxLines(5);
        content.setPadding(0, dp(6), 0, dp(6));
        card.addView(content);

        Button copy = new Button(this);
        copy.setText("Copiar al portapapeles");
        styleButton(copy, false);
        copy.setOnClickListener(v -> {
            rememberIncomingText(clip.text);
            clipboard.setPrimaryClip(OrbitalService.sensitiveTextClip("Paste Shifter · Orbital", clip.text));
            lastObservedClipboard = clip.text;
            statusView.setText("Copia disponible en el portapapeles.");
        });
        card.addView(copy);
    }

    private void rememberIncomingText(String text) {
        recentIncomingText.add(text);
        while (recentIncomingText.size() > 60) {
            Iterator<String> iterator = recentIncomingText.iterator();
            iterator.next();
            iterator.remove();
        }
    }

    private TextView heading(String value) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextColor(0xfff5f1fb);
        view.setTextSize(17);
        view.setTypeface(null, android.graphics.Typeface.BOLD);
        return view;
    }

    private LinearLayout.LayoutParams params(int width, int height) {
        return new LinearLayout.LayoutParams(width, height);
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    private final class OrbitalRingsView extends View {
        private final android.graphics.Paint paint = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private boolean connected;
        OrbitalRingsView(Context context) { super(context); }
        void setConnected(boolean value) { if (connected != value) { connected = value; invalidate(); } }
        @Override protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);
            float cx = getWidth() / 2f, cy = getHeight() / 2f, r = Math.min(cx, cy) * .82f;
            paint.setStyle(android.graphics.Paint.Style.STROKE);
            paint.setStrokeWidth(dp(1));
            paint.setColor(connected ? 0x997e59b2 : 0x66574b6b);
            canvas.drawCircle(cx, cy, r * .78f, paint);
            canvas.save(); canvas.rotate(-24, cx, cy);
            paint.setColor(connected ? 0xffac77ec : 0xff706180);
            paint.setStrokeWidth(dp(1.4f));
            canvas.drawOval(cx-r, cy-r*.40f, cx+r, cy+r*.40f, paint);
            canvas.restore();
            paint.setStyle(android.graphics.Paint.Style.FILL);
            paint.setColor(connected ? 0xffe3c3ff : 0xff887a9c);
            canvas.drawCircle(cx+r*.81f, cy-r*.31f, dp(3.2f), paint);
            paint.setColor(connected ? 0xff9e6be0 : 0xff665a79);
            canvas.drawCircle(cx-r*.85f, cy+r*.27f, dp(2.2f), paint);
        }
    }

    private final class OrbitalMarkView extends View {
        private final android.graphics.Paint paint = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Bitmap mark;
        OrbitalMarkView(Context context) { super(context); mark = android.graphics.BitmapFactory.decodeResource(getResources(), cl.pasteshifter.orbital.R.drawable.paste_shifter_mark); }
        @Override protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);
            float cx=getWidth()/2f, cy=getHeight()/2f, radius=Math.min(cx,cy)*0.57f;
            canvas.save(); canvas.rotate(-28,cx,cy); paint.setStyle(android.graphics.Paint.Style.STROKE); paint.setStrokeWidth(dp(1.6f)); paint.setColor(0xff9b62dc);
            canvas.drawOval(cx-radius,cy-radius*0.50f,cx+radius,cy+radius*0.50f,paint); canvas.restore();
            if(mark!=null){ paint.setStyle(android.graphics.Paint.Style.FILL); android.graphics.RectF dst=new android.graphics.RectF(cx-dp(21),cy-dp(21),cx+dp(21),cy+dp(21)); canvas.drawBitmap(mark,null,dst,paint); }
            paint.setColor(0xffc69df0); paint.setStyle(android.graphics.Paint.Style.FILL); canvas.drawCircle(cx+radius*0.75f,cy-radius*0.36f,dp(4),paint);
            paint.setColor(0xff6f31b3); canvas.drawCircle(cx-radius*0.82f,cy+radius*0.24f,dp(2.4f),paint);
        }
    }

    @Override public void onStatus(String status) { showFriendlyStatus(status); }

    @Override public void onPairingComparisonCode(String code) {
        LinearLayout content=new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL);
        TextView explanation=secondary("Comprueba que este número también aparece en tu Mac.");
        explanation.setTextSize(13); content.addView(explanation);
        TextView number=heading(code); number.setTextSize(30); number.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams codeParams=params(-1,dp(70));codeParams.topMargin=dp(8);content.addView(number,codeParams);
        showSheet("Confirma que eres tú","Verificación de seguridad",content,"Entendido",null);
    }

    @Override public void onPaired(OrbitalAndroidSession.PairedMac mac) {
        // The comparison code is only relevant while the Mac is waiting for
        // approval. Once approval succeeds and the new pin is persisted, close
        // that sheet so the connected screen is unobstructed.
        hideSheet();
        needsRepairPairing=false;
        preferences.edit().remove(KEY_REPAIR_REQUIRED).apply();
        pairedMac = mac;
        preferences.edit().putString(KEY_MAC_ID, mac.macId.toString())
                .putString(KEY_PIN, encodeHex(mac.certificateFingerprintSha256)).apply();
        renderPairedState();
        statusView.setText("Mac emparejado y conexión autenticada.");
        closeSession(null);
        OrbitalService.start(this);
        updateConnectionButton();
    }

    @Override public void onClip(OrbitalAndroidSession.ReceivedClip clip) {
        addReceivedClip(clip);
        statusView.setText("Copia lista para pegar");
    }
}
