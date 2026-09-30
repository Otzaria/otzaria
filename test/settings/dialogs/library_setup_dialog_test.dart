import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/dialogs/library_setup_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// navigatorKey — כדי ש-UiSnack ימצא Overlay להודעות השגיאה.
Widget _host(void Function(BuildContext) onOpen) => MaterialApp(
  navigatorKey: navigatorKey,
  home: Scaffold(
    body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => onOpen(ctx),
        child: const Text('פתח'),
      ),
    ),
  ),
);

Future<void> _openSetup(
  WidgetTester tester, {
  String defaultTargetPath = '/default/library',
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      (ctx) => showLibrarySetupDialog(
        context: ctx,
        defaultTargetPath: defaultTargetPath,
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

Future<void> _openUpdate(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      (ctx) => showLibrarySetupDialog(
        context: ctx,
        defaultTargetPath: '/lib',
        currentLibraryPath: '/lib/books',
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

VoidCallback? _actionOnPressed(WidgetTester tester, String text) {
  final btn = tester.widget<ActionButton>(
    find.byWidgetPredicate((w) => w is ActionButton && w.text == text),
  );
  return btn.onPressed;
}

Future<void> _select(WidgetTester tester, String optionTitle) async {
  // מקישים על כותרת האפשרות (ולא על מרכז השורה, שעלול לפגוע בכפתור ה-trailing).
  final title = find.text(optionTitle);
  await tester.ensureVisible(title);
  await tester.tap(title);
  await tester.pumpAndSettle();
}

/// בורר תיקייה מזויף: מחזיר תמיד את [folder], כמו משתמש שבחר אותה.
class _FolderFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  _FolderFilePickerPlatform(this.folder);
  final String folder;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => folder;
}

/// קובץ שנבחר בבורר — כמו העותק שאנדרואיד יוצר במטמון.
final class _PickedFile extends PlatformFile {
  _PickedFile(this._path);
  final String _path;

  @override
  String get name => p.basename(_path);

  @override
  Uri get uri => Uri.file(_path);

  @override
  XFile get xFile => XFile(_path);

  @override
  int? lengthSync() => File(_path).lengthSync();

  @override
  Future<int> length() => File(_path).length();

  @override
  Future<Uint8List> readAsBytes() => File(_path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(_path).openRead().map(Uint8List.fromList);
}

/// בורר קבצים מזויף שמדמה את ההעתקה למטמון באנדרואיד: מדווח picking, מחכה
/// ל-[finishCopy], ורק אז מחזיר את הקובץ (או זורק, כשההעתקה נכשלת).
class _CopyingFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  _CopyingFilePickerPlatform(this.path, {this.fails = false});
  final String path;
  final bool fails;
  final _copy = Completer<void>();

  void finishCopy() => _copy.complete();

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    onFileLoading?.call(FilePickerStatus.picking);
    await _copy.future;
    onFileLoading?.call(FilePickerStatus.done);
    if (fails) {
      throw PlatformException(
        code: 'unknown_path',
        message: 'Failed to retrieve path.',
      );
    }
    return _PickedFile(path);
  }
}

/// בורר שמתעד את הסיומות שהתבקשו ומחזיר את [path].
class _RecordingFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  _RecordingFilePickerPlatform(this.path);
  final String path;
  List<String>? allowedExtensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.allowedExtensions = allowedExtensions;
    return _PickedFile(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('showLibrarySetupDialog — ללא ספרייה קיימת (הגדרה)', () {
    testWidgets('כותרת: "הגדרת ספריית אוצריא"', (tester) async {
      await _openSetup(tester);
      expect(find.text('הגדרת ספריית אוצריא'), findsOneWidget);
    });

    testWidgets('כרטיס "פעולה" מוצג, ואפשרות ההעברה לא', (tester) async {
      await _openSetup(tester);
      expect(find.text('פעולה'), findsOneWidget);
      expect(find.text('העברת תוכן התיקייה'), findsNothing);
    });

    testWidgets('פעולות המקור: הורדה, שימוש במקום, תיקייה וארכיון', (
      tester,
    ) async {
      await _openSetup(tester);
      expect(find.text('הורדת הספרייה'), findsOneWidget);
      expect(find.text('שימוש בספרייה קיימת במקומה'), findsOneWidget);
      expect(find.text('בחירת תיקייה מהמחשב'), findsOneWidget);
      expect(find.text('בחירת קובץ דחוס'), findsOneWidget);
    });

    testWidgets('בחירת "שימוש במקום" מסתירה את מקטע היעד', (tester) async {
      await _openSetup(tester, defaultTargetPath: '/default/library');
      expect(find.text('תיקיית היעד לספריית אוצריא'), findsOneWidget);

      await _select(tester, 'שימוש בספרייה קיימת במקומה');
      expect(find.text('תיקיית היעד לספריית אוצריא'), findsNothing);
      expect(find.text('מיקום ברירת מחדל'), findsNothing);
    });

    testWidgets('"שימוש במקום": אישור מושבת עד שנבחרת תיקייה', (tester) async {
      await _openSetup(tester, defaultTargetPath: '/default/library');
      await _select(tester, 'שימוש בספרייה קיימת במקומה');
      // יעד ברירת המחדל קיים, אך לשימוש במקום הוא לא רלוונטי — נדרשת תיקייה.
      expect(_actionOnPressed(tester, 'אישור'), isNull);
      expect(_actionOnPressed(tester, 'בחר תיקייה קיימת'), isNotNull);
      expect(find.textContaining('הקבצים יישארו במקומם'), findsOneWidget);
    });

    testWidgets('מקטע היעד: "תיקיית היעד לספריית אוצריא" עם ברירת מחדל', (
      tester,
    ) async {
      await _openSetup(tester, defaultTargetPath: '/default/library');
      expect(find.text('תיקיית היעד לספריית אוצריא'), findsOneWidget);
      expect(find.text('מיקום ברירת מחדל'), findsOneWidget);
    });

    testWidgets('לאפשרות יש רדיו ב-leading (בלי אייקון ובלי Checkbox)', (
      tester,
    ) async {
      await _openSetup(tester);
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('הורדת הספרייה'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.leading, isNotNull);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('כפתור "אישור" פעיל בהורדה כשיש יעד ברירת מחדל', (
      tester,
    ) async {
      await _openSetup(tester, defaultTargetPath: '/default/library');
      // הורדה היא ברירת המחדל; היעד מולא מברירת המחדל → אישור פעיל.
      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });

    testWidgets('כפתור "אישור" מושבת כשאין יעד', (tester) async {
      await _openSetup(tester, defaultTargetPath: '');
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });
  });

  group('showLibrarySetupDialog — עם ספרייה קיימת (עדכון)', () {
    testWidgets('כותרת: "עדכון ספריית אוצריא"', (tester) async {
      await _openUpdate(tester);
      expect(find.text('עדכון ספריית אוצריא'), findsOneWidget);
    });

    testWidgets('העברה גלויה; הורדה/ייבוא מקובצים תחת "מחיקה וייבוא ספרייה"', (
      tester,
    ) async {
      await _openUpdate(tester);
      expect(find.text('פעולה'), findsOneWidget);
      expect(find.text('העברת תוכן התיקייה'), findsOneWidget);
      // שימוש במקום אינו מחיקה-והחלפה — הוא יושב מחוץ למקטע הנפרש.
      expect(find.text('שימוש בספרייה קיימת במקומה'), findsOneWidget);
      expect(find.text('החלפת הספרייה בספרייה אחרת'), findsOneWidget);
      // המקטע מקופל כברירת מחדל — אפשרויות ההחלפה מוסתרות.
      expect(find.text('הורדת הספרייה מחדש'), findsNothing);
      expect(find.text('בחירת תיקייה מהמחשב'), findsNothing);
      expect(find.text('בחירת קובץ דחוס'), findsNothing);

      // פריסת המקטע חושפת את אפשרויות ההחלפה.
      await _select(tester, 'החלפת הספרייה בספרייה אחרת');
      expect(find.text('הורדת הספרייה מחדש'), findsOneWidget);
      expect(find.text('בחירת תיקייה מהמחשב'), findsOneWidget);
      expect(find.text('בחירת קובץ דחוס'), findsOneWidget);
    });

    testWidgets('מקטע היעד מוצג בכותרת "מיקום חדש"', (tester) async {
      await _openUpdate(tester);
      expect(find.text('מיקום חדש'), findsOneWidget);
    });

    testWidgets('כותרת המשנה של המקטע מציינת שהספרייה הקיימת תוחלף', (
      tester,
    ) async {
      await _openUpdate(tester);
      expect(find.textContaining('הספרייה הקיימת תוחלף'), findsOneWidget);
    });

    testWidgets(
      'אישור מושבת בהעברה ליעד הנוכחי (no-op) ובייבוא ללא תיקיית מקור',
      (tester) async {
        await _openUpdate(tester);
        // ברירת המחדל "העברה" + יעד זהה למיקום הנוכחי → אין מה להעביר, אישור מושבת.
        expect(_actionOnPressed(tester, 'אישור'), isNull);

        // מעבר ל"בחירת תיקייה" ללא בחירת מקור → אישור מושבת.
        await _select(tester, 'החלפת הספרייה בספרייה אחרת');
        await _select(tester, 'בחירת תיקייה מהמחשב');
        expect(_actionOnPressed(tester, 'אישור'), isNull);
        // כפתור בחירת המקור מוצג.
        expect(find.text('בחר תיקייה'), findsOneWidget);
        expect(find.text('בחר קובץ ספרייה'), findsOneWidget);
      },
    );
  });

  testWidgets('בחירת קובץ דחוס מקבלת גם קובץ ספרייה seforim.zdb בודד', (
    tester,
  ) async {
    final picker = _RecordingFilePickerPlatform('/bundle/seforim.zdb');
    FilePickerPlatform.instance = picker;
    await _openSetup(tester, defaultTargetPath: '/default/library');
    await _select(tester, 'בחירת קובץ דחוס');
    await tester.ensureVisible(find.text('בחר קובץ דחוס'));
    await tester.tap(find.text('בחר קובץ דחוס'));
    await tester.pumpAndSettle();

    expect(picker.allowedExtensions, containsAll(['zip', 'zst', 'zdb']));
    expect(find.text('seforim.zdb'), findsOneWidget);
    expect(_actionOnPressed(tester, 'אישור'), isNotNull);
  });

  group('בחירת תיקייה שאינה ניתנת לקריאה (issue #1219)', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('otzaria_1219_');
      await File('${temp.path}/seforim.db').writeAsBytes([0, 1, 2]);
      FilePickerPlatform.instance = _FolderFilePickerPlatform(temp.path);
    });

    tearDown(() async {
      debugLibraryFolderReadProbe = null;
      await temp.delete(recursive: true);
    });

    test(
      'scanLibraryFolderAssets: קובץ קיים אך חסום לקריאה → לא נגיש',
      () async {
        debugLibraryFolderReadProbe = (file) async =>
            throw PathAccessException(file.path, const OSError('EACCES', 13));
        final scan = await scanLibraryFolderAssets(temp.path);
        expect(scan.readable, isFalse);
        expect(scan.found, isEmpty);
      },
    );

    test('scanLibraryFolderAssets: קובץ קריא → זוהה', () async {
      final scan = await scanLibraryFolderAssets(temp.path);
      expect(scan.readable, isTrue);
      expect(scan.found, contains('ספריית הספרים (seforim.db)'));
    });

    testWidgets('תיקייה חסומה: הנחיה לבחור את הקובץ, ואישור מושבת', (
      tester,
    ) async {
      debugLibraryFolderReadProbe = (file) async =>
          throw PathAccessException(file.path, const OSError('EACCES', 13));
      await _openSetup(tester);
      await _select(tester, 'בחירת תיקייה מהמחשב');
      await tester.ensureVisible(find.text('בחר תיקייה'));
      // הסריקה קוראת מהדיסק — IO אמיתי אינו מסתיים תחת FakeAsync.
      await tester.runAsync(() async {
        await tester.tap(find.text('בחר תיקייה'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('אין הרשאת קריאה לתיקייה'), findsOneWidget);
      expect(find.text('כל הקבצים זוהו'), findsNothing);
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });

    testWidgets('תיקייה קריאה: כל הקבצים זוהו ואישור פעיל', (tester) async {
      await _openSetup(tester);
      await _select(tester, 'בחירת תיקייה מהמחשב');
      await tester.ensureVisible(find.text('בחר תיקייה'));
      // הסריקה קוראת מהדיסק — IO אמיתי אינו מסתיים תחת FakeAsync.
      await tester.runAsync(() async {
        await tester.tap(find.text('בחר תיקייה'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('הספרייה (seforim.db)'), findsNothing);
      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });
  });

  group('בחירת קובץ ספרייה — העתקה למטמון באנדרואיד (issue #1360)', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('otzaria_1360_');
      await File('${temp.path}/seforim.db').writeAsBytes([0, 1, 2]);
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    Future<void> tapPickFile(WidgetTester tester) async {
      await _openSetup(tester);
      await _select(tester, 'בחירת תיקייה מהמחשב');
      await tester.ensureVisible(find.text('בחר קובץ ספרייה'));
      await tester.tap(find.text('בחר קובץ ספרייה'));
      await tester.pump();
    }

    testWidgets('בזמן ההעתקה: הודעה, הכפתורים והאישור מושבתים; בסיום — זוהה', (
      tester,
    ) async {
      final picker = _CopyingFilePickerPlatform('${temp.path}/seforim.db');
      FilePickerPlatform.instance = picker;
      await tapPickFile(tester);

      expect(
        find.textContaining('המערכת מעתיקה את הקובץ שנבחר'),
        findsOneWidget,
      );
      expect(_actionOnPressed(tester, 'בחר קובץ ספרייה'), isNull);
      expect(_actionOnPressed(tester, 'בחר תיקייה'), isNull);
      expect(_actionOnPressed(tester, 'אישור'), isNull);

      picker.finishCopy();
      await tester.pumpAndSettle();

      expect(find.textContaining('המערכת מעתיקה'), findsNothing);
      expect(_actionOnPressed(tester, 'בחר קובץ ספרייה'), isNotNull);
      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });

    testWidgets('כשל בהעתקה למטמון מוצג למשתמש ומשחרר את הכפתורים', (
      tester,
    ) async {
      final picker = _CopyingFilePickerPlatform(
        '${temp.path}/seforim.db',
        fails: true,
      );
      FilePickerPlatform.instance = picker;
      await tapPickFile(tester);
      expect(_actionOnPressed(tester, 'בחר קובץ ספרייה'), isNull);

      picker.finishCopy();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('העתקת הקובץ שנבחר נכשלה'), findsOneWidget);
      expect(_actionOnPressed(tester, 'בחר קובץ ספרייה'), isNotNull);
      expect(_actionOnPressed(tester, 'אישור'), isNull);
      // ההודעה נעלמת מעצמה — מנקים כדי שלא יישאר טיימר פתוח.
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('בזמן ההעתקה אי אפשר להחליף פעולה', (tester) async {
      final picker = _CopyingFilePickerPlatform('${temp.path}/seforim.db');
      FilePickerPlatform.instance = picker;
      await tapPickFile(tester);

      final download = find.text('הורדת הספרייה');
      await tester.ensureVisible(download);
      await tester.tap(download);
      final archive = find.text('בחירת קובץ דחוס');
      await tester.ensureVisible(archive);
      await tester.tap(archive);
      await tester.pump();

      picker.finishCopy();
      await tester.pumpAndSettle();

      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });
  });
}
