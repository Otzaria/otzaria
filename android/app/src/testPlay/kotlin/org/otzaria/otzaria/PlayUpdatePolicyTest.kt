package org.otzaria.otzaria

import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlayUpdatePolicyTest {
    @Test fun prefersFlexibleAndDoesNotLaunchDisallowedTypes() {
        assertEquals(AppUpdateType.FLEXIBLE, PlayUpdatePolicy.type(true, true, false))
        assertEquals(AppUpdateType.IMMEDIATE, PlayUpdatePolicy.type(false, true, false))
        assertNull(PlayUpdatePolicy.type(false, false, false))
    }
    @Test fun resumesOnlyTheExistingImmediateFlow() {
        assertEquals(AppUpdateType.IMMEDIATE, PlayUpdatePolicy.type(true, true, true))
        assertNull(PlayUpdatePolicy.type(true, false, true))
    }
    @Test fun unavailableTypesDoNotBlockAnAlreadyDownloadedUpdate() {
        assertEquals("unavailable", PlayUpdatePolicy.stage(InstallStatus.UNKNOWN, true, false, false))
        assertEquals("unavailable", PlayUpdatePolicy.stage(InstallStatus.UNKNOWN, false, true, false))
        assertEquals("downloading", PlayUpdatePolicy.stage(InstallStatus.DOWNLOADING, true, false, false))
        assertEquals("ready", PlayUpdatePolicy.stage(InstallStatus.DOWNLOADED, true, false, false))
        assertEquals("installing", PlayUpdatePolicy.stage(InstallStatus.INSTALLING, true, false, false))
    }
    @Test fun downloadedDoesNotMeanInstalledAndCancellationIsDistinct() {
        assertEquals("ready", PlayUpdatePolicy.stage(InstallStatus.DOWNLOADED, true, false))
        assertEquals("installing", PlayUpdatePolicy.stage(InstallStatus.INSTALLING, true, false))
        assertEquals("completed", PlayUpdatePolicy.stage(InstallStatus.INSTALLED, false, false))
        assertEquals("cancelled", PlayUpdatePolicy.stage(InstallStatus.CANCELED, true, false))
        assertEquals("confirmation", PlayUpdatePolicy.stage(InstallStatus.UNKNOWN, false, true))
    }
}
