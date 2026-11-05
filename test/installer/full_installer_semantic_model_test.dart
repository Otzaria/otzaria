import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:path/path.dart' as p;

String _routine(String script, String signature) {
  final start = script.indexOf(signature);
  expect(start, isNonNegative, reason: signature);
  return script.substring(start, script.indexOf('\nend;', start) + 5);
}

void main() {
  String? compiler;
  try {
    if (Process.runSync('fpc', ['-iV']).exitCode == 0) compiler = 'fpc';
  } on ProcessException {
    // בדיקת Pascal משתמשת בשגרה האמיתית; ללא FPC נשארת בדיקת החוזה.
  }
  final helper = File(
    'installer/preserve_semantic_model.iss',
  ).readAsStringSync();
  final folderConstant =
      "SemanticModelFolderName = '$kSemanticModelFolderName';";
  final skip = compiler == null ? 'נדרש Free Pascal לבדיקת ההחלפה' : false;

  for (final variant in [
    (
      name: 'FULL',
      script: 'installer/otzaria_full.iss',
      routine: 'procedure ExtractEmbeddedLibraryArchives();',
      invoke: 'ExtractEmbeddedLibraryArchives();',
      oldBooks: 'SelectedBooksPath',
      parts: false,
    ),
    (
      name: 'LibraryParts',
      script: 'installer/otzaria.iss',
      routine: 'procedure ExtractLibraryArchives(const BooksPath: String);',
      invoke: 'ExtractLibraryArchives(SelectedBooksPath);',
      oldBooks: 'BooksPath',
      parts: true,
    ),
  ]) {
    group(variant.name, () {
      final script = File(variant.script).readAsStringSync();
      late final String swap;
      late Directory work;
      late String executable;

      test('משמר את תיקיית המודל שהאפליקציה קוראת לפני החלפת הספרייה', () {
        expect(helper, contains(folderConstant));
        expect(script, contains('#include "preserve_semantic_model.iss"'));
        expect(
          swap.indexOf('CopySemanticModelDirectory('),
          allOf(
            isNonNegative,
            lessThan(swap.indexOf('RenameFile(${variant.oldBooks}')),
          ),
        );
      });

      setUpAll(() async {
        swap = _routine(script, variant.routine);
        if (compiler == null) return;
        work = await Directory.systemTemp.createTemp(
          'installer-semantic-model-',
        );
        executable = p.join(
          work.path,
          'probe${Platform.isWindows ? '.exe' : ''}',
        );
        final template = File(
          'test/installer/support/full_installer_semantic_model_probe.pas',
        ).readAsStringSync();
        final source = template
            .replaceFirst('{MODEL_FOLDER_CONSTANT}', folderConstant)
            .replaceFirst('{PARTS_VARIANT}', '${variant.parts}')
            .replaceFirst('{INSTALL_ROUTINE}', variant.invoke)
            .replaceFirst(
              '{EXTRACTED_ROUTINES}',
              [
                _routine(helper, 'function CopySemanticModelDirectory('),
                swap,
              ].join('\n\n'),
            );
        final input = File(p.join(work.path, 'probe.pas'));
        await input.writeAsString(source);
        final result = await Process.run(compiler!, [
          '-o$executable',
          input.path,
        ], workingDirectory: work.path);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      });

      tearDownAll(() async {
        if (compiler != null) await work.delete(recursive: true);
      });

      for (final scenario in {
        'success': 'החלפת הספרייה משמרת את כל קבצי המודל ונתוני ההדגשה',
        'no-model': 'התקנה בלי מודל קודם אינה יוצרת מודל ריק',
        'empty-model': 'תיקיית מודל ריקה אינה מכשילה את העדכון',
        'copy-fails': 'כשל העתקת מודל משאיר את הספרייה והמודל המקוריים',
        'mkdir-fails': 'כשל יצירת תיקיית המודל עוצר לפני החלפת הספרייה',
        'swap-fails': 'כשל בהחלפת הספרייה משחזר גם את המודל הקיים',
        if (variant.parts) ...{
          'index-swap-fails': 'כשל בהחלפת האינדקס משחזר גם את הספרייה והמודל',
          'no-index': 'עדכון ללא אינדקס משמר את האינדקס והמודל הקיימים',
        },
      }.entries) {
        test(scenario.value, () async {
          final result = await Process.run(executable, [
            scenario.key,
            work.path,
          ]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        }, skip: skip);
      }
    });
  }
}
