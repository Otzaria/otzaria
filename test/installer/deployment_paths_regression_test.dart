import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String routine(String script, String signature) {
  final start = script.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  return script.substring(start, script.indexOf('\nend;', start) + 5);
}

// Evaluates the guard's actual expression with documented Inno path primitives.
bool acceptsLibraryDirectory(String script, String path) {
  final guard = routine(script, 'function IsSafeLibraryDirectory(');
  expect(guard, contains('Drive := ExtractFileDrive(Path);'));
  final expression = RegExp(
    r'Result := (.*?);',
    dotAll: true,
  ).firstMatch(guard)!.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
  final drive = p.windows.rootPrefix(path).replaceFirst(RegExp(r'\\$'), '');
  return expression
      .split(' and ')
      .map((clause) {
        final length = RegExp(
          r'^\(Length\(Path\) >= (\d+)\)$',
        ).firstMatch(clause);
        if (length != null) return path.length >= int.parse(length.group(1)!);
        if (clause == "(Drive <> '')") return drive.isNotEmpty;
        if (clause ==
            '(Pos(Lowercase(AddBackslash(Drive)), Lowercase(Path)) = 1)') {
          return path.toLowerCase().startsWith('${drive.toLowerCase()}\\');
        }
        throw UnsupportedError('Unrecognized Inno guard clause: $clause');
      })
      .every((value) => value);
}

void main() {
  final script = File('installer/otzaria.iss').readAsStringSync();
  // ההודעות של המתקין ב-[CustomMessages] של שכבת התצוגה.
  final messages = File(
    'installer/otzaria_ui_installer.iss',
  ).readAsStringSync();
  for (final fixture in <String, bool>{
    r'D:': false,
    'D:\\': false,
    r'\\server\share': false,
    r'\\server\share\books': true,
    r'D:\custom-root': true,
    r'D:\X': false,
    r'books\nested': false,
    r'D:books': false,
    r'\books': false,
  }.entries) {
    test('library target safety: ${fixture.key}', () {
      expect(acceptsLibraryDirectory(script, fixture.key), fixture.value);
    });
  }
  test(
    'unsafe configured roots stop before accepting a DB record or payload',
    () {
      final resolve = routine(
        script,
        'function GetLibraryBooksPath(): String;\nvar',
      );
      final guard = resolve.indexOf(
        'if not IsSafeLibraryDirectory(CustomPath)',
      );
      expect(guard, greaterThan(0));
      final record = resolve.indexOf('DatabasePath := Trim(');
      expect(guard, lessThan(record));
      expect(resolve.substring(guard, record), contains("Result := '';"));
      expect(resolve.substring(guard, record), contains('exit;'));
      final next = routine(script, 'function NextButtonClick(');
      expect(
        next,
        contains("if HasLibraryPayload and (GetLibraryBooksPath() = '')"),
      );
      expect(next, contains("CustomMessage('UnsafeLibraryRoot')"));
      expect(messages, contains('אין להתקין ספרייה בשורש כונן או שיתוף'));
    },
  );
  test('missing part000 cannot bypass library or index validation', () {
    final probe = routine(script, 'function HasSplitArchiveParts(');
    expect(probe, contains("ArchiveName + '.part-*'"));
    final prepare = routine(script, 'function PrepareLibraryParts(');
    expect(
      prepare,
      contains("HasSplitArchiveParts(SourceDir, '{#LibraryArchiveName}')"),
    );
    expect(
      prepare,
      contains("HasSplitArchiveParts(SourceDir, '{#IndexArchiveName}')"),
    );
    expect(prepare, isNot(contains('.part-000')));
    expect(prepare, contains("PrepareSplitArchive('library.manifest.json'"));
    expect(
      prepare,
      contains("PrepareSplitArchive('library_index.manifest.json'"),
    );
  });
  test(
    'legacy root-only records resolve a unique nested DB or stop on ambiguity',
    () {
      final resolve = routine(
        script,
        'function GetLibraryBooksPath(): String;\nvar',
      );
      expect(resolve, contains('FindFirst(AddBackslash(CustomPath)'));
      expect(resolve, contains("FindRec.Name + '\\seforim.db'"));
      expect(resolve, contains('CandidateCount = 1'));
      expect(resolve, contains('CandidateCount > 1'));
      expect(resolve, contains("Result := '';"));
      final next = routine(script, 'function NextButtonClick(');
      expect(next, contains("GetLibraryBooksPath() = ''"));
      expect(next, contains('Result := False;'));
    },
  );
  test(
    'stale DB records cannot bypass discovery of the existing nested DB',
    () {
      final resolve = routine(
        script,
        'function GetLibraryBooksPath(): String;\nvar',
      );
      final recordCheck = resolve.indexOf(
        "if FileExists(AddBackslash(DatabasePath) + 'seforim.db')",
      );
      expect(recordCheck, greaterThan(0));
      expect(recordCheck, lessThan(resolve.indexOf('Result := DatabasePath')));
      expect(resolve, contains("ReadLibraryPathRecord(GetDataDir(''))"));
      expect(resolve, contains("AddBackslash(GetDataDir(''))"));
      expect(
        routine(script, 'function NextButtonClick('),
        contains("CustomMessage('UnsafeLibraryRoot')"),
      );
      expect(messages, contains('עדכנו תחילה את התוכנה בלבד'));
    },
  );
  test(
    'nested DB keeps app index adjacent to configured root, semantic beside DB',
    () {
      final index = routine(script, 'function GetLibraryIndexPath(');
      expect(index, contains('ExtractFileDir(CustomPath)'));
      final extract = routine(script, 'procedure ExtractLibraryArchives(');
      expect(
        extract,
        contains('TargetIndex := GetLibraryIndexPath(BooksPath)'),
      );
      expect(extract, contains('IndexBackup := TargetIndex'));
      expect(
        extract,
        contains('IndexStagingRoot := ExtractFileDir(TargetIndex)'),
      );
      expect(
        extract,
        contains('UnpackArchive(PreparedIndexArchive, IndexStagingRoot,'),
      );
      expect(
        routine(script, 'function GetSemanticImportDir('),
        contains('ExtractFileDir(GetLibraryBooksPath())'),
      );
    },
  );
}
