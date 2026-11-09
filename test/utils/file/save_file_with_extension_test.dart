import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('save_file_ext_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('חלון מקור שכבר פורק מבטל את הבורר לפני הפלאגין', (tester) async {
    late BuildContext origin;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          origin = context;
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    var invoked = false;
    final result = await withFilePickerOwner<String>(origin, (_) async {
      invoked = true;
      return 'wrong window';
    });
    expect(invoked, isFalse);
    expect(result, isNull);
  });

  testWidgets('בורר macOS מקבל את מזהה תצוגת המקור כולל אפס', (tester) async {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Object? arguments;
    messenger.setMockMethodCallHandler(channel, (call) async {
      arguments = call.arguments;
      return '/tmp/chosen';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    late BuildContext origin;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          origin = context;
          return const SizedBox.shrink();
        },
      ),
    );
    final path = await withFilePickerOwner(
      origin,
      (picker) => picker.getDirectoryPath(),
    );
    expect(path, '/tmp/chosen');
    expect((arguments as Map)['viewId'], tester.view.viewId);
  }, skip: !Platform.isMacOS);

  testWidgets('macOS: חלון מקור שנסגר מבטל את הבקשה במקום שגיאה', (
    tester,
  ) async {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'window_not_found');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    late BuildContext origin;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          origin = context;
          return const SizedBox.shrink();
        },
      ),
    );
    final path = await withFilePickerOwner(
      origin,
      (picker) => picker.getDirectoryPath(),
    );
    expect(path, isNull);
  }, skip: !Platform.isMacOS);

  test('מחוץ ל-macOS הבורר הוא המופע הרשום', () async {
    final picker = await withFilePickerOwner(null, (picker) async => picker);
    expect(picker, same(FilePickerPlatform.instance));
  }, skip: Platform.isMacOS);

  group('ensureFileExtension', () {
    test(
      'קובץ בלי סיומת — משנה שם ומחזיר את הנתיב החדש (issue #817)',
      () async {
        final file = File('${tempDir.path}${Platform.pathSeparator}calendar');
        await file.writeAsBytes([1, 2, 3]);

        final result = await ensureFileExtension(file.path, 'pdf');

        expect(result, '${file.path}.pdf');
        expect(File(result).existsSync(), isTrue);
        expect(file.existsSync(), isFalse);
      },
    );

    test('סיומת קיימת — הנתיב מוחזר כמות שהוא', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}doc.pdf');
      await file.writeAsBytes([1]);

      expect(await ensureFileExtension(file.path, 'pdf'), file.path);
      expect(file.existsSync(), isTrue);
    });

    test('סיומת קיימת באותיות גדולות — לא משתנה', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}doc.PDF');
      await file.writeAsBytes([1]);

      expect(await ensureFileExtension(file.path, 'pdf'), file.path);
    });

    test('סיומת עם נקודה — לא מוסיף סיומת כפולה', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}book.json');
      await file.writeAsBytes([1, 2, 3]);
      final result = await ensureFileExtension(file.path, '.json');
      expect(result, file.path);
      expect(await file.readAsBytes(), [1, 2, 3]);
    });

    test('סיומת עם נקודה וקובץ חסר סיומת — מוסיף נקודה אחת', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}book');
      await file.writeAsBytes([4, 5]);
      final result = await ensureFileExtension(file.path, '.csv');
      expect(result, '${file.path}.csv');
      expect(await File(result).readAsBytes(), [4, 5]);
      expect(await file.exists(), isFalse);
    });

    test('דחיית סיומת ריקה', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}book');
      await file.writeAsBytes([1]);
      await expectLater(
        ensureFileExtension(file.path, '.'),
        throwsArgumentError,
      );
    });

    test('סיומת אחרת — מוסיף את המבוקשת בסוף', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}doc.txt');
      await file.writeAsBytes([1]);

      final result = await ensureFileExtension(file.path, 'pdf');
      expect(result, '${file.path}.pdf');
    });

    test('יעד קיים — נשמר תחת שם חדש בלי לדרוס קובץ אחר', () async {
      final source = File('${tempDir.path}${Platform.pathSeparator}calendar');
      await source.writeAsBytes([7, 7]);
      final existing = File(
        '${tempDir.path}${Platform.pathSeparator}calendar.pdf',
      );
      await existing.writeAsBytes([1]);

      final result = await ensureFileExtension(source.path, 'pdf');

      expect(result, '${source.path} (1).pdf');
      expect(await File(result).readAsBytes(), [7, 7]);
      expect(await existing.readAsBytes(), [1]);
    });

    test('יעד קיים כמה פעמים — משתמש במספר הפנוי הבא', () async {
      final source = File('${tempDir.path}${Platform.pathSeparator}report');
      await source.writeAsBytes([5, 6]);
      await File('${source.path}.pdf').writeAsBytes([1]);
      await File('${source.path} (1).pdf').writeAsBytes([2]);

      final result = await ensureFileExtension(source.path, 'pdf');

      expect(result, '${source.path} (2).pdf');
      expect(await File(result).readAsBytes(), [5, 6]);
      expect(await File('${source.path}.pdf').readAsBytes(), [1]);
      expect(await File('${source.path} (1).pdf').readAsBytes(), [2]);
    });

    test('שמירות ממקורות שונים אינן דורסות יעד ממוספר משותף', () async {
      final sourceA = File('${tempDir.path}${Platform.pathSeparator}report');
      final sourceB = File('${sourceA.path} (1)');
      final existing = File('${sourceA.path}.pdf');
      await sourceA.writeAsBytes([1, 2]);
      await sourceB.writeAsBytes([3, 4]);
      await existing.writeAsBytes([9]);
      final renameStarted = Completer<void>();
      final resumeRename = Completer<void>();
      final pausedA = _ObservedFile(
        sourceA,
        beforeRename: () {
          renameStarted.complete();
          return resumeRename.future;
        },
      );
      final observedB = _ObservedFile(sourceB);
      final files = <String, File>{
        sourceA.path: pausedA,
        sourceB.path: observedB,
        existing.path: existing,
        '${sourceA.path} (1).pdf': File('${sourceA.path} (1).pdf'),
        '${sourceB.path} (1).pdf': File('${sourceB.path} (1).pdf'),
      };

      final paths = await IOOverrides.runZoned(() async {
        final first = ensureFileExtension(sourceA.path, 'pdf');
        late Future<String> second;
        try {
          await renameStarted.future.timeout(const Duration(seconds: 5));
          second = ensureFileExtension(sourceB.path, 'pdf');
          // בלי תור, B כבר נכנסה ל-exists לפני ה-await הראשון שלה.
          // משלימים אותה לפני A כדי לחשוף דריסה בלי תלות בתזמון הדיסק.
          if (observedB.existsCalled) await second;
        } finally {
          resumeRename.complete();
        }
        return Future.wait([first, second]);
      }, createFile: (path) => files[path]!);

      expect(paths.toSet(), hasLength(2));
      expect(await File(paths[0]).readAsBytes(), [1, 2]);
      expect(await File(paths[1]).readAsBytes(), [3, 4]);
      expect(await existing.readAsBytes(), [9]);
      expect(await sourceA.exists(), isFalse);
      expect(await sourceB.exists(), isFalse);
    });

    for (final failOnRename in [false, true]) {
      test(
        'כשל ${failOnRename ? 'שינוי שם' : 'בדיקת מקור'} אינו חוסם שמירה נוספת',
        () async {
          final source = File('${tempDir.path}${Platform.pathSeparator}failed');
          final next = File('${tempDir.path}${Platform.pathSeparator}next');
          await source.writeAsBytes([1]);
          await next.writeAsBytes([2]);
          final failure = FileSystemException('injected failure', source.path);
          Future<void> fail() async => throw failure;
          final files = <String, File>{
            source.path: _ObservedFile(
              source,
              beforeExists: failOnRename ? null : fail,
              beforeRename: failOnRename ? fail : null,
            ),
            '${source.path}.pdf': File('${source.path}.pdf'),
            next.path: next,
            '${next.path}.pdf': File('${next.path}.pdf'),
          };

          final result = await IOOverrides.runZoned(() async {
            await expectLater(
              ensureFileExtension(source.path, 'pdf'),
              throwsA(same(failure)),
            );
            return ensureFileExtension(
              next.path,
              'pdf',
            ).timeout(const Duration(seconds: 5));
          }, createFile: (path) => files[path]!);

          expect(await source.readAsBytes(), [1]);
          expect(await File('${source.path}.pdf').exists(), isFalse);
          expect(result, '${next.path}.pdf');
          expect(await File(result).readAsBytes(), [2]);
          expect(await next.exists(), isFalse);
        },
      );
    }

    test('הקובץ לא קיים — הנתיב מוחזר בלי שינוי', () async {
      final missing = '${tempDir.path}${Platform.pathSeparator}ghost';
      expect(await ensureFileExtension(missing, 'pdf'), missing);
    });
  });

  group('saveFileWithExtension — הגנת מצב סייפר', () {
    testWidgets(
      'במצב סייפר פעיל — דורש סיסמה, וכשבוטל מחזיר null בלי לפתוח סייר',
      (
        tester,
      ) async {
        final settingsBloc = _MockSettingsBloc();
        final repository = _FakeSettingsRepo();

        whenListen(
          settingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
            protectedModeEnabled: true,
          ),
        );

        String? saveResult;
        late BuildContext testContext;

        await tester.pumpWidget(
          MaterialApp(
            home: RepositoryProvider<SettingsRepository>.value(
              value: repository,
              child: BlocProvider<SettingsBloc>.value(
                value: settingsBloc,
                child: Builder(
                  builder: (context) {
                    testContext = context;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );

        // הרצת saveFileWithExtension ברקע
        final future = saveFileWithExtension(
          fileName: 'test.pdf',
          extension: 'pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
          context: testContext,
        ).then((res) => saveResult = res);

        await tester.pump();
        await tester.pump();

        // מוודאים שדיאלוג הסיסמה נפתח
        expect(find.byType(SaferModePasswordDialog), findsOneWidget);

        // ביטול הדיאלוג
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();

        await future;
        expect(saveResult, isNull);
      },
    );
  });
}

class _ObservedFile extends Fake implements File {
  _ObservedFile(this.file, {this.beforeExists, this.beforeRename});

  final File file;
  final Future<void> Function()? beforeExists;
  final Future<void> Function()? beforeRename;
  bool existsCalled = false;

  @override
  Future<bool> exists() async {
    existsCalled = true;
    if (beforeExists != null) await beforeExists!();
    return file.exists();
  }

  @override
  Future<File> rename(String newPath) async {
    if (beforeRename != null) await beforeRename!();
    return file.rename(newPath);
  }
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepo extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => true;

  @override
  bool verifyProtectedModePassword(String password) => password == '1234';
}
