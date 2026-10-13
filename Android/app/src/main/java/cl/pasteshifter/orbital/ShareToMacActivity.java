package cl.pasteshifter.orbital;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ShortcutManager;
import android.os.Build;
import android.os.Bundle;
import android.widget.Toast;

/** Small handoff activity: choosing “Mi Mac” sends the selected text and returns. */
public final class ShareToMacActivity extends Activity {
    private static final String DEVICE_PREFS = "orbital-device.v1";

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        SharedPreferences preferences = getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE);
        String macID = preferences.getString("paired_mac_id", null);
        String pin = preferences.getString("paired_mac_pin", null);
        CharSequence shared = Intent.ACTION_SEND.equals(getIntent().getAction())
                ? getIntent().getCharSequenceExtra(Intent.EXTRA_TEXT) : null;

        if (macID == null || pin == null || !pin.matches("[0-9a-f]{64}")) {
            Toast.makeText(this, "Conecta Paste Shifter con tu Mac primero.", Toast.LENGTH_LONG).show();
            finish();
            return;
        }
        if (shared == null || !OrbitalProtocol.isValidClipText(shared.toString())) {
            Toast.makeText(this, "Comparte un texto para enviarlo a tu Mac.", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        if (Build.VERSION.SDK_INT >= 30) {
            ShortcutManager shortcuts = getSystemService(ShortcutManager.class);
            if (shortcuts != null) shortcuts.reportShortcutUsed(OrbitalShareTarget.SHORTCUT_ID);
        }
        Intent send = new Intent(this, OrbitalService.class)
                .setAction(OrbitalService.ACTION_SEND_TEXT)
                .putExtra(OrbitalService.EXTRA_TEXT, shared.toString());
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(send); else startService(send);
        Toast.makeText(this, "Enviando a tu Mac por Orbital…", Toast.LENGTH_SHORT).show();
        finish();
    }
}
