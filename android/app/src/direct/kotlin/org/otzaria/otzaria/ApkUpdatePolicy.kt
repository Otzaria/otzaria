package org.otzaria.otzaria

internal class ApkUpdateException(val code: String) : Exception(code)

internal object ApkUpdatePolicy {
    fun recoverStage(
        stage: String,
        sessionExists: Boolean,
        sessionSealed: Boolean,
        working: Boolean,
        hasConfirmation: Boolean,
        confirmationDisplayed: Boolean,
    ): String {
        if (stage !in setOf("installing", "confirmation", "preparing")) return stage
        if (!sessionExists || (!working && !sessionSealed)) return "interrupted"
        if (stage == "confirmation" && !hasConfirmation && !confirmationDisplayed) return "interrupted"
        return stage
    }

    fun validate(
        installedPackage: String,
        candidatePackage: String,
        installedVersion: Long,
        candidateVersion: Long,
        installedSigners: Set<String>,
        candidateSigners: Set<String>,
        candidateHistory: Set<String>,
        deviceSdk: Int,
        minSdk: Int,
    ) {
        if (candidatePackage != installedPackage) throw ApkUpdateException("PACKAGE_MISMATCH")
        if (candidateVersion <= installedVersion) throw ApkUpdateException("VERSION_NOT_NEWER")
        if (minSdk > deviceSdk) throw ApkUpdateException("INCOMPATIBLE_DEVICE")
        if (installedSigners.isEmpty() || candidateSigners.isEmpty()) {
            throw ApkUpdateException("SIGNATURE_MISMATCH")
        }
        val sameSigners = installedSigners == candidateSigners
        val rotatedForward = installedSigners.size == 1 && candidateSigners.size == 1 &&
            candidateHistory.containsAll(installedSigners)
        if (!sameSigners && !rotatedForward) throw ApkUpdateException("SIGNATURE_MISMATCH")
    }
}
