#!/usr/bin/env python3
"""APK metadata contracts; the CI matrix also exercises the real SDK tools."""

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tool.release import android_release_metadata as metadata


BADGING = """package: name='org.otzaria.otzaria' versionCode='99803' versionName='0.9.98'
sdkVersion:'23'
targetSdkVersion:'36'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.REQUEST_INSTALL_PACKAGES'
native-code: 'x86_64' 'armeabi-v7a' 'arm64-v8a'
"""
SIGNERS = f"""Verifies
Signer #1 certificate SHA-256 digest: {'AB' * 32}
Signer #1 public key SHA-256 digest: {'cd' * 32}
Source Stamp Signer certificate SHA-256 digest: {'ef' * 32}
"""
SCRIPT = Path(metadata.__file__).resolve()


class AndroidMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="android metadata ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.apk = self.root / "otzaria-android.apk"
        self.apk.write_bytes(bytes(range(256)) * 9000)
        self.output = self.root / "otzaria-android.json"
        self.calls = self.root / "calls.jsonl"
        self.sdk = self.root / "build tools"
        self.sdk.mkdir()
        self.tool("aapt", BADGING)
        self.tool("apksigner", SIGNERS)

    def tool(self, name, output, exit_code=0, before=""):
        path = self.sdk / name
        path.write_text(
            "#!/usr/bin/env python3\n"
            "import json, pathlib, sys\n"
            f"with open({str(self.calls)!r}, 'a') as log:\n"
            f"    log.write(json.dumps([{name!r}, *sys.argv[1:]]) + '\\n')\n"
            f"{before}\n"
            f"print({output!r})\n"
            f"sys.exit({exit_code})\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def run_cli(self, *extra):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--apk", str(self.apk),
             "--output", str(self.output), "--build-tools", str(self.sdk),
             "--distribution", "direct", *extra],
            capture_output=True, text=True, timeout=15,
        )

    def describe(self):
        return metadata.describe_apk(self.apk, self.sdk, "direct")

    def test_cli_uses_verified_apk_facts_and_actual_streamed_bytes(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        actual = json.loads(self.output.read_text())
        self.assertEqual(actual, {
            "schemaVersion": 1,
            "applicationId": "org.otzaria.otzaria",
            "versionCode": 99803,
            "versionName": "0.9.98",
            "minSdk": 23,
            "targetSdk": 36,
            "abis": ["arm64-v8a", "armeabi-v7a", "x86_64"],
            "apk": {
                "name": "otzaria-android.apk",
                "size": self.apk.stat().st_size,
                "sha256": hashlib.sha256(self.apk.read_bytes()).hexdigest(),
            },
            "signingCertificateSha256": ["ab" * 32],
        })
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [
            ["apksigner", "verify", "--verbose", "--print-certs", str(self.apk)],
            ["aapt", "dump", "badging", str(self.apk)],
        ])
        first = self.output.read_bytes()
        self.assertEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.output.read_bytes(), first)

    def test_legacy_apk_filename_remains_valid(self):
        self.apk = self.apk.rename(self.root / "app-release.apk")
        self.assertEqual(self.describe()["apk"]["name"], "app-release.apk")

    def test_failed_signature_verification_does_not_publish_metadata(self):
        self.tool("apksigner", SIGNERS, exit_code=1)
        self.output.write_text("existing metadata")
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("apksigner failed", result.stderr)
        self.assertEqual(self.output.read_text(), "existing metadata")
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_unsigned_or_stamp_only_output_is_not_a_signing_identity(self):
        for text in ("", f"Source Stamp Signer certificate SHA-256 digest: {'ef' * 32}",
                     f"Signer #1 public key SHA-256 digest: {'cd' * 32}"):
            with self.subTest(text=text), self.assertRaises(metadata.MetadataError):
                metadata.parse_signers(text)

    def test_multiple_signers_are_normalized_and_sorted(self):
        text = SIGNERS + f"Signer #2 certificate SHA-256 digest: {'01' * 32}\n"
        self.assertEqual(metadata.parse_signers(text), ["01" * 32, "ab" * 32])

    def test_aapt_failure_does_not_publish_metadata(self):
        self.tool("aapt", BADGING, exit_code=2)
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_distribution_checks_the_apk_permissions(self):
        without_permission = BADGING.replace(
            "uses-permission: name='android.permission.REQUEST_INSTALL_PACKAGES'\n", "")
        metadata.verify_distribution(BADGING, "direct", False)
        metadata.verify_distribution(without_permission, "play", False)
        for text, channel in ((BADGING, "play"), (without_permission, "direct")):
            with self.subTest(channel=channel), self.assertRaises(metadata.MetadataError):
                metadata.verify_distribution(text, channel, False)

    def test_release_rejects_debuggable_apk_but_ci_can_inspect_it(self):
        self.tool("aapt", BADGING + "application-debuggable\n")
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.run_cli("--allow-debug").returncode, 0)

    def test_changed_apk_cannot_pair_old_signature_with_new_bytes(self):
        self.tool("aapt", BADGING, before=f"pathlib.Path({str(self.apk)!r}).write_bytes(b'changed')")
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("APK changed", result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_ambiguous_or_foreign_badging_is_rejected(self):
        cases = [
            BADGING.replace("org.otzaria.otzaria", "org.otzaria.otzaria.startupprobe"),
            BADGING.replace("versionCode='99803'", "versionCode='x'"),
            BADGING.replace("versionCode='99803'", "versionCode='99803' versionCodeMajor='1'"),
            BADGING.replace("sdkVersion:'23'", "sdkVersion:'Preview'"),
            BADGING.replace("targetSdkVersion:'36'\n", ""),
            BADGING + "sdkVersion:'24'\n",
            BADGING.replace("native-code: 'x86_64' 'armeabi-v7a' 'arm64-v8a'\n", ""),
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(metadata.MetadataError):
                metadata.parse_badging(text)

    def test_schema_rejects_invalid_values_and_unsafe_asset_names(self):
        valid = self.describe()
        changes = [
            ("schemaVersion", True), ("schemaVersion", 2),
            ("applicationId", "other.package"), ("versionCode", 0),
            ("versionCode", True), ("versionName", ""),
            ("minSdk", 37), ("targetSdk", "36"), ("abis", []),
            ("abis", ["arm64-v8a", "arm64-v8a"]), ("abis", [False]),
            ("apk", {"name": "../otzaria-android.apk", "size": 1, "sha256": "ab" * 32}),
            ("apk", {"name": "x.apk", "size": False, "sha256": "ab" * 32}),
            ("apk", {"name": "x.apk", "size": 1, "sha256": "bad"}),
            ("signingCertificateSha256", []),
            ("signingCertificateSha256", ["not-a-certificate"]),
            ("signingCertificateSha256", ["ab" * 32, "ab" * 32]),
        ]
        for field, value in changes:
            candidate = copy.deepcopy(valid)
            candidate[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(metadata.MetadataError):
                metadata.validate_metadata(candidate)

    def test_output_cannot_replace_the_apk(self):
        before = self.apk.read_bytes()
        result = self.run_cli("--output", str(self.apk))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.apk.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
