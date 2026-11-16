package org.otzaria.otzaria;

import org.junit.Test;
import static org.junit.Assert.*;

public class DownloadNetworkStateTest {
    @Test public void unknownAndCellularAreDeniedUntilWifiCapabilitiesArrive() {
        DownloadNetworkState state = new DownloadNetworkState();
        assertFalse(state.onAvailable("default"));
        assertEquals(Boolean.FALSE, state.onCapabilities("default", false, true));
        assertEquals(Boolean.TRUE, state.onCapabilities("default", true, false));
        assertEquals(Boolean.FALSE, state.onCapabilities("default", false, false));
    }

    @Test public void vpnCapabilitiesCanChangeWithoutReplacingTheDefaultNetwork() {
        DownloadNetworkState state = new DownloadNetworkState();
        state.onAvailable("vpn");
        assertEquals(Boolean.TRUE, state.onCapabilities("vpn", true, false));
        assertEquals(Boolean.FALSE, state.onCapabilities("vpn", true, true));
        assertEquals(Boolean.FALSE, state.onCapabilities("vpn", false, true));
        assertEquals(Boolean.TRUE, state.onCapabilities("vpn", true, false));
    }

    @Test public void oldNetworkCallbacksCannotEraseTheNewDefault() {
        DownloadNetworkState state = new DownloadNetworkState();
        state.onAvailable("old");
        state.onCapabilities("old", true, false);
        assertFalse(state.onAvailable("new"));
        assertEquals(Boolean.TRUE, state.onCapabilities("new", true, false));
        assertNull(state.onLost("old"));
        assertNull(state.onCapabilities("old", false, true));
        assertTrue(state.onAvailable("new"));
    }

    @Test public void initialSnapshotSurvivesTheMatchingAvailableCallback() {
        DownloadNetworkState state = new DownloadNetworkState();
        state.onAvailable(new String("network-id"));
        state.onCapabilities(new String("network-id"), true, false);
        assertTrue(state.onAvailable(new String("network-id")));
        assertEquals(Boolean.FALSE, state.onLost(new String("network-id")));
        assertFalse(state.onAvailable("replacement"));
    }
}
