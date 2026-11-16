package org.otzaria.otzaria;

import java.util.Objects;

final class DownloadNetworkState {
    private Object active;
    private boolean wifiOnly;

    boolean onAvailable(Object network) {
        if (!Objects.equals(active, network)) {
            active = network;
            wifiOnly = false;
        }
        return wifiOnly;
    }

    Boolean onCapabilities(Object network, boolean wifi, boolean cellular) {
        if (!Objects.equals(active, network)) return null;
        wifiOnly = wifi && !cellular;
        return wifiOnly;
    }

    Boolean onLost(Object network) {
        if (!Objects.equals(active, network)) return null;
        reset();
        return false;
    }

    void reset() {
        active = null;
        wifiOnly = false;
    }
}
