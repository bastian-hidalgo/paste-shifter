package cl.pasteshifter.orbital;

import android.content.Intent;
import android.os.Build;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

public final class OrbitalTileService extends TileService {
    @Override public void onStartListening() { super.onStartListening(); update(); }
    @Override public void onClick() {
        super.onClick();
        if (OrbitalService.isActive(this)) OrbitalService.pause(this); else OrbitalService.start(this);
        update();
    }
    private void update() {
        Tile tile = getQsTile(); if (tile == null) return;
        boolean active = OrbitalService.isActive(this);
        tile.setState(active ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setLabel(active ? "Orbital activo" : "Orbital");
        tile.setSubtitle(active ? "Paste Shifter" : "Pausado");
        tile.updateTile();
    }
}
