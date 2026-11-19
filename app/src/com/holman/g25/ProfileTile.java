package com.holman.g25;

import android.graphics.drawable.Icon;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Quick Settings tile: each tap cycles the g25_gaming profile Normal -> Demonio -> Eco. */
public class ProfileTile extends TileService {
    private static final String CYCLE = "sh /data/adb/modules/g25_gaming/profile.sh next";
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onStartListening() {
        refresh();
    }

    @Override
    public void onClick() {
        Tile tile = getQsTile();
        tile.setLabel("…");
        tile.updateTile();
        new Thread(() -> {
            try {
                Runtime.getRuntime().exec(new String[] {"su", "-c", CYCLE}).waitFor();
            } catch (Exception ignored) {
                // refresh() then shows the unchanged profile
            }
            main.post(this::refresh);
        }).start();
    }

    /** Shows the profile saved by profile.sh in Settings.Global. */
    private void refresh() {
        Tile tile = getQsTile();
        if (tile == null) return;  // panel already closed; onStartListening refreshes next time
        String p = Settings.Global.getString(getContentResolver(), "g25_profile");
        int icon;
        if ("demon".equals(p)) {
            tile.setLabel("Demonio");
            icon = android.R.drawable.ic_media_ff;
        } else if ("eco".equals(p)) {
            tile.setLabel("Eco");
            icon = android.R.drawable.ic_lock_idle_low_battery;
        } else {
            tile.setLabel("Normal");
            icon = android.R.drawable.ic_media_play;
        }
        tile.setIcon(Icon.createWithResource("android", icon));
        tile.setState("demon".equals(p) || "eco".equals(p) ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.updateTile();
    }
}
