package org.otzaria.otzaria

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class ApkUpdatePolicyTest {
    private fun validate(
        candidatePackage: String = "org.otzaria.otzaria",
        version: Long = 101,
        installedSigners: Set<String> = setOf("A"),
        newSigners: Set<String> = setOf("A"),
        history: Set<String> = newSigners,
        minSdk: Int = 24,
    ) = ApkUpdatePolicy.validate("org.otzaria.otzaria", candidatePackage, 100, version,
        installedSigners, newSigners, history, 35, minSdk)

    private fun rejected(code: String, action: () -> Unit) {
        try {
            action()
            fail("Expected $code")
        } catch (error: ApkUpdateException) {
            assertEquals(code, error.code)
        }
    }

    @Test fun acceptsSignedUpgrade() { validate() }
    @Test fun rejectsDifferentPackageAndDowngrades() {
        rejected("PACKAGE_MISMATCH") { validate(candidatePackage = "other.app") }
        rejected("VERSION_NOT_NEWER") { validate(version = 100) }
        rejected("VERSION_NOT_NEWER") { validate(version = 99) }
    }
    @Test fun rejectsWrongOrMissingSignatures() {
        rejected("SIGNATURE_MISMATCH") { validate(newSigners = setOf("B")) }
        rejected("SIGNATURE_MISMATCH") { validate(newSigners = emptySet()) }
        rejected("SIGNATURE_MISMATCH") { validate(installedSigners = emptySet()) }
    }
    @Test fun acceptsForwardRotationButRejectsRollbackAndPartialMultisigning() {
        validate(newSigners = setOf("B"), history = setOf("A", "B"))
        rejected("SIGNATURE_MISMATCH") { validate(installedSigners = setOf("B"), newSigners = setOf("A")) }
        validate(installedSigners = setOf("A", "B"), newSigners = setOf("A", "B"))
        rejected("SIGNATURE_MISMATCH") { validate(installedSigners = setOf("A", "B"), newSigners = setOf("A"), history = setOf("A", "B")) }
    }
    @Test fun rejectsUnsupportedSdk() { rejected("INCOMPATIBLE_DEVICE") { validate(minSdk = 36) } }

    @Test fun recoversProcessDeathBeforeCommitAndLostConfirmation() {
        assertEquals("interrupted", ApkUpdatePolicy.recoverStage("installing", true, false, false, false, false))
        assertEquals("interrupted", ApkUpdatePolicy.recoverStage("preparing", true, false, false, false, false))
        assertEquals("interrupted", ApkUpdatePolicy.recoverStage("confirmation", true, true, false, false, false))
        assertEquals("interrupted", ApkUpdatePolicy.recoverStage("installing", false, false, false, false, false))
    }
    @Test fun doesNotInterruptLiveCopyOrDisplayedConfirmation() {
        assertEquals("installing", ApkUpdatePolicy.recoverStage("installing", true, false, true, false, false))
        assertEquals("confirmation", ApkUpdatePolicy.recoverStage("confirmation", true, true, false, true, false))
        assertEquals("confirmation", ApkUpdatePolicy.recoverStage("confirmation", true, true, false, false, true))
        assertEquals("completed", ApkUpdatePolicy.recoverStage("completed", false, false, false, false, false))
    }
}
