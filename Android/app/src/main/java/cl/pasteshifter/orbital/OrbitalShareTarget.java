package cl.pasteshifter.orbital;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import java.util.Collections;

/** Publishes the paired Mac as a one-tap Android Sharesheet destination. */
final class OrbitalShareTarget {
    static final String SHORTCUT_ID = "orbital-send-to-mac";
    static final String CATEGORY = "cl.pasteshifter.orbital.TEXT_SHARE_TARGET";

    private OrbitalShareTarget() {}

    static void refresh(Context context, boolean paired) {
        ShortcutManager manager = context.getSystemService(ShortcutManager.class);
        if (manager == null) return;
        if (!paired) {
            manager.removeDynamicShortcuts(Collections.singletonList(SHORTCUT_ID));
            return;
        }
        Intent shareIntent = new Intent(Intent.ACTION_SEND)
                .setClass(context, ShareToMacActivity.class)
                .setType("text/plain");
        ShortcutInfo target = new ShortcutInfo.Builder(context, SHORTCUT_ID)
                .setShortLabel("Mi Mac")
                .setLongLabel("Paste Shifter · enviar a mi Mac")
                .setIcon(Icon.createWithResource(context, R.mipmap.ic_launcher))
                .setIntent(shareIntent)
                .setCategories(Collections.singleton(CATEGORY))
                .setLongLived(true)
                .build();
        manager.setDynamicShortcuts(Collections.singletonList(target));
    }
}
