import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ארכיון מפוצל נבנה מחדש ומאומת לפי ה-manifest', () async {
    final temp = Directory.systemTemp.createTempSync('otzaria_release_parts_');
    addTearDown(() => temp.deleteSync(recursive: true));

    final source = File(p.join(temp.path, 'indexed-full.tar.zst'));
    final sourceBytes = List<int>.generate(1025, (index) => index % 251);
    source.writeAsBytesSync(sourceBytes);
    final partsDirectory = Directory(p.join(temp.path, 'parts'));

    final split = await Process.run('bash', [
      'tool/release/split_release_asset.sh',
      source.path,
      partsDirectory.path,
      '128',
    ]);
    expect(split.exitCode, 0, reason: '${split.stdout}\n${split.stderr}');

    final manifestFile = File(
      p.join(partsDirectory.path, 'indexed-full.tar.zst.manifest.json'),
    );
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final parts = manifest['parts'] as List<dynamic>;
    expect(parts, hasLength(9));
    expect(
      parts.every((part) => (part as Map<String, dynamic>)['size'] <= 128),
      isTrue,
    );

    final reassembled = p.join(temp.path, 'reassembled.tar.zst');
    final assemble = await Process.run('bash', [
      'tool/release/assemble_split_asset.sh',
      manifestFile.path,
      reassembled,
    ]);
    expect(
      assemble.exitCode,
      0,
      reason: '${assemble.stdout}\n${assemble.stderr}',
    );
    expect(File(reassembled).readAsBytesSync(), sourceBytes);

    final manifestSummary = p.join(temp.path, 'manifest-summary.txt');
    final parseManifest = await Process.run('pwsh', [
      '-NoLogo',
      '-NoProfile',
      '-File',
      'installer/read_indexed_library_manifest.ps1',
      '-ManifestPath',
      manifestFile.path,
      '-OutputPath',
      manifestSummary,
    ]);
    expect(
      parseManifest.exitCode,
      0,
      reason: '${parseManifest.stdout}\n${parseManifest.stderr}',
    );
    final summaryLines = File(manifestSummary).readAsLinesSync();
    expect(summaryLines.first, startsWith('archive|indexed-full.tar.zst|'));
    expect(
      summaryLines.where((line) => line.startsWith('part|')),
      hasLength(9),
    );

    final embeddedManifestDirectory = Directory(
      p.join(temp.path, 'embedded-manifest'),
    )..createSync();
    final embeddedManifest = File(
      p.join(embeddedManifestDirectory.path, 'indexed_library.manifest.json'),
    );
    manifestFile.copySync(embeddedManifest.path);
    final powerShellOutput = p.join(temp.path, 'reassembled-pwsh.tar.zst');
    final powerShellAssemble = await Process.run('pwsh', [
      '-NoLogo',
      '-NoProfile',
      '-File',
      'tool/release/assemble_split_asset.ps1',
      embeddedManifest.path,
      powerShellOutput,
      partsDirectory.path,
    ]);
    expect(
      powerShellAssemble.exitCode,
      0,
      reason: '${powerShellAssemble.stdout}\n${powerShellAssemble.stderr}',
    );
    expect(File(powerShellOutput).readAsBytesSync(), sourceBytes);

    final firstPart = File(
      p.join(
        partsDirectory.path,
        (parts.first as Map<String, dynamic>)['name'],
      ),
    );
    firstPart.writeAsBytesSync([0], mode: FileMode.append);
    final rejectedOutput = p.join(temp.path, 'rejected.tar.zst');
    final rejectedAssembly = await Process.run('pwsh', [
      '-NoLogo',
      '-NoProfile',
      '-File',
      'tool/release/assemble_split_asset.ps1',
      embeddedManifest.path,
      rejectedOutput,
      partsDirectory.path,
    ]);
    expect(rejectedAssembly.exitCode, isNot(0));
    expect(File(rejectedOutput).existsSync(), isFalse);
  });

  test('ה-workflow מפריד בין המתקין לחלקי הספרייה שמתחת ל-2 GiB', () {
    final workflow = File(
      '.github/workflows/build-and-announce.yml',
    ).readAsStringSync();

    expect(workflow, contains('build-release-index'));
    expect(workflow, contains('otzaria-library-full-indexed'));
    expect(workflow, contains('1992294400'));
    expect(workflow, contains('split_release_asset.sh'));
    expect(workflow, contains('compression-level: 0'));
    expect(workflow, contains('/DIndexedSplitFull=1'));
    expect(workflow, contains('otzaria-windows-installer-full-indexed'));
    expect(workflow, contains('התקנה לא־מקוונת בווינדוס'));
    expect(workflow, contains('indexed_library.manifest.json'));
    expect(
      workflow,
      contains(
        'cp -al "\$GITHUB_WORKSPACE/\$BUNDLE_ROOT/אוצריא" '
        '"\$INDEXED_LIBRARY_ROOT/books"',
      ),
    );
  });
}
