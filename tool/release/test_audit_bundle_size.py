import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import textwrap
from pathlib import Path
import tempfile
import stat
import warnings
import zipfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import audit_bundle_size as audit


class BundleSizeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name).resolve()
        self.bundle = self.parent / 'bundle'
        self.bundle.mkdir()

    def write(self, name, data):
        path = self.bundle / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def arguments(self, *extra):
        return [str(self.bundle), '--target', 'test-x64', '--source-commit', 'abc',
                '--output', str(self.parent / 'report.json'), *extra]

    def assert_bad_cli(self, *extra):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            audit.main(self.arguments(*extra))
        self.assertEqual(error.exception.code, 1)

    def test_empty_bundle(self):
        result = audit.inventory(self.bundle)
        self.assertEqual(result['bundle_file_bytes'], 0)
        self.assertEqual(result['file_count'], 0)
        self.assertIsNone(result['installed_size_bytes'])
        self.assertIsNone(result['duplicate_content_groups'])

    def test_categories_sum_to_total_and_unicode_paths_survive(self):
        self.write('data/flutter_assets/fonts/אות.ttf', b'font')
        self.write('lib/libapp.so', b'aot')
        self.write('lib/libpdfium.so.1', b'native')
        self.write('data/flutter_assets/data.json', b'{}')
        result = audit.inventory(self.bundle)
        self.assertEqual(result['category_bytes'], {'assets': 2, 'dart_aot': 3, 'fonts': 4, 'native': 6})
        self.assertEqual(result['bundle_file_bytes'], 15)
        self.assertEqual(sum(result['category_bytes'].values()), 15)
        self.assertEqual(result['unique_file_bytes'], 15)

    def test_categories_for_windows_macos_and_android(self):
        examples = {'App.framework/App': 'dart_aot', 'App.framework.dSYM/DWARF/App': 'debug_symbols',
                    'data/APP.SO': 'dart_aot', 'lib/arm64-v8a/libapp.so': 'dart_aot',
                    'flutter_windows.dll': 'native', 'Runner.exe': 'native',
                    'Flutter.framework/Versions/A/Flutter': 'native',
                    'App.framework/Resources/flutter_assets/data.json': 'assets',
                    'App.framework/Resources/Info.plist': 'other',
                    'otzaria': 'native', 'lib/foo.a': 'native', 'foo.dylib': 'native',
                    'foo.pdb': 'debug_symbols', 'foo.so.debug': 'debug_symbols',
                    'model.onnx': 'models', 'font.woff2': 'fonts', 'LICENSE': 'other'}
        for path, expected in examples.items():
            with self.subTest(path=path):
                self.assertEqual(audit.category(path), expected)

    def test_symlinks_are_not_followed_even_outside_bundle(self):
        outside = self.parent / 'outside'
        outside.mkdir()
        (outside / 'large').write_bytes(b'x' * 5000)
        try:
            (self.bundle / 'outside').symlink_to(outside, target_is_directory=True)
            (self.bundle / 'broken').symlink_to('missing')
            (self.bundle / 'cycle').symlink_to(self.bundle, target_is_directory=True)
        except OSError as error:
            self.skipTest(f'host does not permit symlinks: {error}')
        result = audit.inventory(self.bundle, duplicates=True)
        self.assertEqual(result['bundle_file_bytes'], 0)
        self.assertEqual(len(result['symlinks']), 3)

    def test_hard_links_have_separate_logical_and_unique_totals(self):
        first = self.write('one.dll', b'content')
        try:
            os.link(first, self.bundle / 'two.dll')
        except OSError as error:
            self.skipTest(f'host does not permit hard links: {error}')
        result = audit.inventory(self.bundle, duplicates=True)
        self.assertEqual(result['bundle_file_bytes'], 14)
        self.assertEqual(result['unique_file_bytes'], 7)
        self.assertEqual(len(result['duplicate_content_groups']), 1)

    def test_duplicates_require_content_not_just_size(self):
        self.write('a', b'abc')
        self.write('b', b'abc')
        self.write('c', b'xyz')
        self.write('empty', b'')
        result = audit.inventory(self.bundle, duplicates=True)
        self.assertEqual(result['duplicate_content_groups'], [
            {'bytes_per_file': 3, 'sha256': hashlib.sha256(b'abc').hexdigest(), 'paths': ['a', 'b']}])

    def test_unique_size_files_do_not_need_hashing(self):
        self.write('a', b'a')
        self.write('b', b'bb')
        with patch.object(audit, 'sha256', side_effect=AssertionError('unexpected read')):
            audit.inventory(self.bundle, duplicates=True)

    def test_hash_reads_bounded_chunks(self):
        class BoundedStream(io.BytesIO):
            def read(self, size=-1):
                if size <= 0 or size > 1024 * 1024:
                    raise AssertionError(f'unbounded read: {size}')
                return super().read(size)
        data = b'a' * (3 * 1024 * 1024 + 9)
        with patch.object(Path, 'open', return_value=BoundedStream(data)):
            self.assertEqual(audit.sha256(Path('unused')), hashlib.sha256(data).hexdigest())

    def test_mutated_file_is_rejected(self):
        self.write('a', b'abc')
        self.write('b', b'abc')
        original = audit.sha256
        def mutate(path):
            digest = original(path)
            path.write_bytes(b'changed-size')
            return digest
        with patch.object(audit, 'sha256', side_effect=mutate), self.assertRaisesRegex(ValueError, 'changed'):
            audit.inventory(self.bundle, duplicates=True)

    def test_stable_order_and_largest_limit(self):
        for index in reversed(range(25)):
            self.write(f'{index:02}.txt', b'x')
        first = audit.inventory(self.bundle)
        self.assertEqual(first, audit.inventory(self.bundle))
        self.assertEqual(len(first['largest_files']), 20)
        self.assertEqual([item['path'] for item in first['largest_files']], [f'{i:02}.txt' for i in range(20)])

    def test_download_and_lock_are_separate_from_payload(self):
        self.write('payload.dll', b'1234567890')
        download = self.parent / 'dist.zip'
        download.write_bytes(b'zip')
        lock = self.parent / 'pubspec.lock'
        lock.write_bytes(b'lock')
        self.assertEqual(audit.main(self.arguments('--download', str(download), '--lockfile', str(lock))), 0)
        report = json.loads((self.parent / 'report.json').read_text(encoding='utf-8'))
        self.assertEqual(report['bundle_file_bytes'], 10)
        self.assertEqual(report['download_bytes'], 3)
        self.assertEqual(report['download_sha256'], hashlib.sha256(b'zip').hexdigest())
        self.assertIsNone(report['installed_size_bytes'])
        self.assertEqual(report['lockfiles'][0]['sha256'], hashlib.sha256(b'lock').hexdigest())

    def test_output_inside_bundle_is_rejected_without_creating_it(self):
        output = self.bundle / 'report.json'
        self.assert_bad_cli('--output', str(output))
        self.assertFalse(output.exists())

    def test_output_cannot_overwrite_download_or_lockfile(self):
        for option in ('--download', '--lockfile'):
            protected = self.parent / 'protected'
            protected.write_bytes(b'original')
            self.assert_bad_cli(option, str(protected), '--output', str(protected))
            self.assertEqual(protected.read_bytes(), b'original')

    def test_missing_inputs_fail_without_report(self):
        self.assert_bad_cli('--download', str(self.parent / 'missing'))
        self.assertFalse((self.parent / 'report.json').exists())
        self.assert_bad_cli('--lockfile', str(self.parent / 'missing'))
        self.assertFalse((self.parent / 'report.json').exists())

    def test_non_directory_bundle_is_rejected(self):
        path = self.write('file', b'file')
        with self.assertRaises(ValueError):
            audit.inventory(path)

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'POSIX special-file test')
    def test_special_files_fail_instead_of_hanging(self):
        os.mkfifo(self.bundle / 'pipe')
        with self.assertRaisesRegex(ValueError, 'unsupported special file'):
            audit.inventory(self.bundle)

    def test_zip_reports_compressed_and_payload_bytes_separately(self):
        archive = self.parent / 'app.apk'
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as output:
            output.writestr('lib/arm64-v8a/libapp.so', b'a' * 10000)
            output.writestr('assets/flutter_assets/font.otf', b'font')
        report = audit.zip_inventory(archive)
        self.assertEqual(report['bundle_file_bytes'], 10004)
        self.assertIsNone(report['unique_file_bytes'])
        self.assertIsNone(report['installed_size_bytes'])
        self.assertEqual(audit.main([str(archive), *self.arguments()[1:]]), 0)
        result = json.loads((self.parent / 'report.json').read_text(encoding='utf-8'))
        self.assertEqual(result['download_bytes'], archive.stat().st_size)
        self.assertLess(result['download_bytes'], result['bundle_file_bytes'])

    def test_zip_symlink_is_not_regular_file(self):
        archive = self.parent / 'mac.zip'
        link = zipfile.ZipInfo('Framework/Current')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(archive, 'w') as output:
            output.writestr(link, b'A')
            output.writestr('Framework/A/file.dylib', b'native')
        report = audit.zip_inventory(archive)
        self.assertEqual(report['bundle_file_bytes'], 6)
        self.assertEqual(report['symlinks'], [{'path': 'Framework/Current', 'target': None}])

    def test_zip_rejects_duplicate_and_ambiguous_paths(self):
        for names in [('a', 'a'), ('a', './a'), ('../escape',), ('/absolute',), ('C:/drive',)]:
            archive = self.parent / 'bad.zip'
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(archive, 'w') as output:
                    for name in names:
                        output.writestr(name, b'a')
            with self.subTest(names=names), self.assertRaises(ValueError):
                audit.zip_inventory(archive)

    def test_corrupt_archive_fails_cleanly(self):
        path = self.parent / 'bad.zip'
        path.write_bytes(b'not a zip')
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            audit.main([str(path), *self.arguments()[1:]])
        self.assertEqual(error.exception.code, 1)

    def test_archive_duplicates_option_is_not_silently_ignored(self):
        archive = self.parent / 'file.zip'
        with zipfile.ZipFile(archive, 'w') as output:
            output.writestr('a', b'a')
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            audit.main([str(archive), *self.arguments()[1:], '--duplicates'])
        self.assertEqual(error.exception.code, 1)

    def test_existing_output_hard_link_cannot_modify_bundle(self):
        source = self.write('payload', b'original')
        output = self.parent / 'report.json'
        try:
            os.link(source, output)
        except OSError as error:
            self.skipTest(f'host does not permit hard links: {error}')
        audit.main(self.arguments())
        self.assertEqual(source.read_bytes(), b'original')
        self.assertEqual(json.loads(output.read_text())['bundle_file_bytes'], 8)
        self.assertEqual(list(self.parent.glob('.size-audit-*.tmp')), [])

    def test_zero_direntry_inode_uses_fresh_stat_for_hard_links(self):
        first = self.write('one.dll', b'content')
        second = self.bundle / 'two.dll'
        try:
            os.link(first, second)
        except OSError as error:
            self.skipTest(f'host does not permit hard links: {error}')
        entries = []
        for path in (first, second):
            metadata = path.stat(follow_symlinks=False)
            # Model the documented Windows DirEntry cache on every platform.
            missing_identity = SimpleNamespace(st_mode=metadata.st_mode,
                                               st_size=metadata.st_size,
                                               st_ino=0, st_dev=0)
            entry = SimpleNamespace(path=str(path),
                                    stat=lambda follow_symlinks, value=missing_identity: value)
            entries.append(entry)
        with patch.object(audit.os, 'scandir', return_value=contextlib.nullcontext(entries)):
            result = audit.inventory(self.bundle)
        self.assertEqual(result['bundle_file_bytes'], 14)
        self.assertEqual(result['unique_file_bytes'], 7)

    def test_zip_raw_names_are_checked_before_host_normalization(self):
        # Patch equal-length raw names in both ZIP headers. Constructing ZipInfo
        # with a backslash on Windows normalizes it before writing the fixture.
        for raw_name in (bytes((97, 92, 98)), bytes((97, 0, 98))):
            archive = self.parent / 'raw-name.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                output.writestr('a-b', b'data')
            original = archive.read_bytes()
            self.assertEqual(original.count(b'a-b'), 2)
            archive.write_bytes(original.replace(b'a-b', raw_name))
            with self.subTest(raw_name=raw_name), self.assertRaises(ValueError):
                audit.zip_inventory(archive)


@unittest.skipUnless(shutil.which('bash'), 'workflow requires bash')
class AndroidAuditWorkflowTest(unittest.TestCase):
    def test_native_build_failures_propagate_without_cache_seeding(self):
        workflow = (Path(__file__).resolve().parents[2] /
                    '.github/workflows/android_code_size_audit.yml').read_text()
        steps = ('Resolve locked dependencies and generate source catalogs',
                 'Build one-ABI release with Flutter analyze-size')
        for step in steps:
            block = workflow.split(f'      - name: {step}\n', 1)[1]
            block = block.split('\n      - ', 1)[0].split('        run: |\n', 1)[1]
            script = textwrap.dedent(block)
            for status, message in ((42, 'PDFium checksum mismatch'),
                                    (17, 'compiler failure')):
                with self.subTest(step=step, failure=message), tempfile.TemporaryDirectory() as folder:
                    cache = Path(folder) / '.dart_tool/hooks_runner/shared/pdfium_dart/build/root'
                    cache.mkdir(parents=True)
                    stubs = f'''flutter() {{
  if [ "$1" = pub ]; then return 0; fi
  printf '%s\\n' '{message}' >&2
  return {status}
}}
dart() {{ printf '%s\\n' '{message}' >&2; return {status}; }}
curl() {{ printf 'unexpected PDFium download' >&2; return 99; }}
git() {{ printf fixture; }}
export RUNNER_TEMP="$PWD" GH_TOKEN=fixture
'''
                    result = subprocess.run([shutil.which('bash'), '-c', stubs + script],
                                            cwd=folder, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, status, result.stderr)
                    self.assertIn(message, result.stderr)
                    self.assertNotIn('unexpected PDFium download', result.stderr)
                    self.assertEqual(list(cache.iterdir()), [])

    def test_direct_flavor_preserves_arm64_size_artifact(self):
        workflow = (Path(__file__).resolve().parents[2] /
                    '.github/workflows/android_code_size_audit.yml').read_text()
        block = workflow.split('      - name: Build one-ABI release with Flutter analyze-size\n', 1)[1]
        block = block.split('\n      - ', 1)[0].split('        run: |\n', 1)[1]
        with tempfile.TemporaryDirectory() as folder:
            stubs = '''flutter() { printf '%s\\n' "$@" > "$RUNNER_TEMP/arguments"; }
git() { printf fixture; }
find() { return 0; }
export RUNNER_TEMP="$PWD"
printf '%s' "$RUNNER_TEMP/code-size"
'''
            result = subprocess.run([shutil.which('bash'), '-c', stubs + textwrap.dedent(block)],
                                    cwd=folder, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((Path(folder) / 'arguments').read_text().splitlines(), [
                'build', 'apk', '--release', '--flavor', 'direct',
                '--target-platform', 'android-arm64', '--analyze-size',
                f'--code-size-directory={result.stdout}',
                '--dart-define=OTZARIA_BUILD_COMMIT=fixture'])
        self.assertIn('name: android-arm64-dart-code-size', workflow)
        self.assertIn('path: ${{ runner.temp }}/code-size/', workflow)


if __name__ == '__main__':
    unittest.main()
