"""Preparation contract without network access or a native toolchain."""

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile


class PreparationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="domless_prepare_test_")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.here = self.root / "repo/tool/perf_probe/domless_runtime"
        self.here.mkdir(parents=True)
        shutil.copyfile(Path(__file__).with_name("prepare.py"), self.here / "prepare.py")
        self.environment = 'globalThis.fixture = "עברית → ✓";'
        (self.here / "environment.js").write_text(self.environment, encoding="utf-8")
        self.files = {
            "manifest.json": json.dumps(
                {"id": "fixture", "name": "תוסף", "version": "1.0.0"},
                ensure_ascii=False),
            "i18n/en.js": 'globalThis.translations = {name: "עברית → ✓"};',
            "background.html": '<script src="i18n/en.js"></script><script>"שלום";</script>',
        }
        self.engine = self.root / "engine.tar.gz"
        with tarfile.open(self.engine, "w:gz") as archive:
            archive.addfile(tarfile.TarInfo("quickjs-fixture/CMakeLists.txt"), io.BytesIO(b""))
        self.plugin = self.root / "plugin.zip"
        with zipfile.ZipFile(self.plugin, "w") as archive:
            for name, source in self.files.items():
                archive.writestr(name, source.encode("utf-8"))
        self.pins = {
            "description": "קלט בדיקה בלבד",
            "engine": {
                "commit": "fixture",
                "sha256": hashlib.sha256(self.engine.read_bytes()).hexdigest(),
            },
            "plugin": {
                "id": "fixture",
                "version": "1.0.0",
                "sha256": hashlib.sha256(self.plugin.read_bytes()).hexdigest(),
                "files": {name: hashlib.sha256(source.encode("utf-8")).hexdigest()
                          for name, source in self.files.items()},
            },
        }
        self.cache = self.root / "cache"

    def make_source(self):
        source = self.root / "plugin-source"
        source.mkdir()
        for name, content in self.files.items():
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content.encode("utf-8"))
        subprocess.run(["git", "init", "-q", str(source)], check=True)
        subprocess.run(["git", "-C", str(source), "config", "core.autocrlf", "false"], check=True)
        subprocess.run(["git", "-C", str(source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(source), "-c", "user.name=Fixture Test",
                        "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"],
                       check=True)
        commit = subprocess.check_output(
            ["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        self.pins["plugin"]["source"] = {"repository": "fixture/source", "commit": commit}
        return source

    def prepare(self, source=None):
        (self.here / "pins.json").write_text(
            json.dumps(self.pins, ensure_ascii=False), encoding="utf-8")
        # Keep archive verification/extraction real; only native compilation is stubbed.
        runner = """
import json, locale, runpy, subprocess, sys
from unittest.mock import patch
print(json.dumps({'defaultEncoding': locale.getpreferredencoding(False)}))
script = sys.argv.pop(1)
real_run = subprocess.run
def run(command, *args, **kwargs):
    if command[0] == 'cmake':
        return subprocess.CompletedProcess(command, 0)
    return real_run(command, *args, **kwargs)
with patch('subprocess.run', side_effect=run), patch(
        'urllib.request.urlopen', side_effect=AssertionError('Unexpected network access')):
    runpy.run_path(script, run_name='__main__')
"""
        plugin_input = (["--plugin-archive", str(self.plugin)] if source is None
                        else ["--plugin-source", str(source)])
        return subprocess.run(
            [sys.executable, "-c", runner, str(self.here / "prepare.py"),
             "--cache", str(self.cache), "--engine-archive", str(self.engine),
             *plugin_input],
            env={**os.environ, "LC_ALL": "C", "PYTHONCOERCECLOCALE": "0", "PYTHONUTF8": "0"},
            capture_output=True, text=True, encoding="utf-8", check=False,
        )

    def test_unicode_sources_and_json_ignore_locale_encoding(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        encoding = json.loads(result.stdout.splitlines()[0])["defaultEncoding"]
        if sys.platform.startswith("linux"):
            self.assertNotIn(encoding.lower().replace("-", ""), ("utf8", "utf8sig"))
        fixture = json.loads((self.cache / "fixture.json").read_text(encoding="utf-8"))
        defines = json.loads((self.cache / "defines.json").read_text(encoding="utf-8"))
        self.assertEqual(fixture["archiveSha256"], self.pins["plugin"]["sha256"])
        self.assertEqual(fixture["manifest"], json.loads(self.files["manifest.json"]))
        self.assertEqual(fixture["scripts"], [self.files["i18n/en.js"], '"שלום";'])
        self.assertEqual(json.loads(defines["OTZARIA_DOMLESS_FIXTURE"]), fixture)
        self.assertEqual(defines["OTZARIA_DOMLESS_ENVIRONMENT"], self.environment)

    def test_corrupt_engine_archive_is_rejected(self):
        self.engine.write_bytes(self.engine.read_bytes() + b"tampered")
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 mismatch: engine.tar.gz", result.stderr)
        self.assertFalse((self.cache / "fixture.json").exists())

    def test_corrupt_plugin_archive_is_rejected(self):
        self.plugin.write_bytes(self.plugin.read_bytes() + b"tampered")
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 mismatch: plugin.zip", result.stderr)
        self.assertFalse((self.cache / "fixture.json").exists())

    def test_source_hash_mismatch_is_rejected_inside_valid_archive(self):
        self.pins["plugin"]["files"]["i18n/en.js"] = "0" * 64
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unexpected plugin source: i18n/en.js", result.stderr)
        self.assertFalse((self.cache / "fixture.json").exists())

    def test_pinned_checkout_matches_archive_fixture_without_network(self):
        archived = self.prepare()
        self.assertEqual(archived.returncode, 0, archived.stderr)
        archive_fixture = json.loads((self.cache / "fixture.json").read_text(encoding="utf-8"))
        self.assertEqual(archive_fixture["archiveSha256"], self.pins["plugin"]["sha256"])
        source = self.make_source()
        result = self.prepare(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        fixture = json.loads((self.cache / "fixture.json").read_text(encoding="utf-8"))
        self.assertEqual(fixture["manifest"], archive_fixture["manifest"])
        self.assertEqual(fixture["scripts"], archive_fixture["scripts"])
        self.assertIsNone(fixture["archiveSha256"])
        self.assertEqual(fixture["auditedArchiveSha256"], self.pins["plugin"]["sha256"])
        self.assertEqual(fixture["provenance"], {
            "kind": "gitCheckout", **self.pins["plugin"]["source"],
            "verifiedFilesSha256": self.pins["plugin"]["files"],
        })

    def test_checkout_with_wrong_head_is_rejected_even_with_identical_files(self):
        source = self.make_source()
        subprocess.run(["git", "-C", str(source), "-c", "user.name=Fixture Test",
                        "-c", "user.email=fixture@example.invalid", "commit",
                        "--allow-empty", "-qm", "different commit, same files"], check=True)
        result = self.prepare(source)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unexpected plugin source commit", result.stderr)
        self.assertFalse((self.cache / "fixture.json").exists())

    def test_checkout_rejects_changes_to_every_audited_file(self):
        source = self.make_source()
        for name in self.files:
            with self.subTest(name=name):
                path = source / name
                original = path.read_bytes()
                path.write_bytes(original + b"tampered")
                result = self.prepare(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"Unexpected plugin source: {name}", result.stderr)
                self.assertFalse((self.cache / "fixture.json").exists())
                path.write_bytes(original)

    def test_checkout_rejects_missing_files_and_partial_sources(self):
        source = self.make_source()
        for name in self.files:
            with self.subTest(name=name):
                path = source / name
                original = path.read_bytes()
                path.unlink()
                result = self.prepare(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("FileNotFoundError", result.stderr)
                self.assertFalse((self.cache / "fixture.json").exists())
                path.write_bytes(original)

    def test_checkout_rejects_manifest_identity_or_version_disagreement(self):
        source = self.make_source()
        for field in ("id", "version"):
            with self.subTest(field=field):
                original = self.pins["plugin"][field]
                self.pins["plugin"][field] = "different"
                result = self.prepare(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unexpected plugin identity or version", result.stderr)
                self.assertFalse((self.cache / "fixture.json").exists())
                self.pins["plugin"][field] = original


if __name__ == "__main__":
    unittest.main()
