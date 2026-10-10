import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/empty_library/services/library_package/raw_asset_extractor.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/settings/dialogs/library_setup_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:path/path.dart' as p;

import '../../empty_library/library_package_test_support.dart';
import '../../test_helpers/memory_cache_provider.dart';
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

/// בורר תיקייה שסופר קריאות — באנדרואיד מקטע היעד אסור שיפתח אותו.
class _CountingFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  int calls = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    return '/storage/3134-3638/Audiobooks/otzaria';
  }
}

/// מקליט בקשות הורדה ומדווח הצלחה מיד, בלי רשת.
class _RecordingDownloadBloc extends EmptyLibraryBloc {
  _RecordingDownloadBloc() : super(downloadSpaceChecker: (_) async => null);
  final targets = <String?>[];
  EmptyLibraryState? completionState;

  @override
  void add(EmptyLibraryEvent event) {
    if (event is! DownloadLibraryRequested) return super.add(event);
    targets.add(event.targetPath);
    // ignore: invalid_use_of_visible_for_testing_member
    emit(
      completionState ??
          EmptyLibraryDirectorySelected(selectedPath: event.targetPath!),
    );
  }
}

/// תיקייה בזיכרון במקום עץ SAF של אנדרואיד.
class _MemoryFolder extends PackageFolder {
  _MemoryFolder(this.name, this.files, {this.children = const {}});

  final String name;
  final Map<String, List<int>> files;
  final Map<String, _MemoryFolder> children;

  @override
  String get displayName => name;

  @override
  Future<List<PackageFileEntry>> list() async => [
    for (final MapEntry(:key, :value) in files.entries)
      PackageFileEntry(name: key, size: value.length, id: key),
  ];

  @override
  Future<List<String>> folderNames() async => children.keys.toList();

  @override
  Future<PackageFolder?> child(String name) async => children[name];

  @override
  Stream<List<int>> openRead(PackageFileEntry entry) =>
      Stream.value(files[entry.name]!);
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

    testWidgets('פעולות המקור: הורדה, שימוש במקום ותיקייה — בלי ארכיון', (
      tester,
    ) async {
      await _openSetup(tester);
      expect(find.text('הורדת הספרייה'), findsOneWidget);
      expect(find.text('שימוש בספרייה קיימת במקומה'), findsOneWidget);
      expect(find.text('בחירת תיקייה מהמחשב'), findsOneWidget);
      expect(find.textContaining('קובץ דחוס'), findsNothing);
      expect(find.text('בחר קובץ ספרייה'), findsNothing);
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

  group('מקטע היעד באנדרואיד (#2097)', () {
    const internalRoot = '/data/user/0/app/files';
    const sdRoot = '/storage/3134-3638/Android/data/app/files';
    late _CountingFilePickerPlatform picker;
    late _RecordingDownloadBloc bloc;

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      picker = _CountingFilePickerPlatform();
      FilePickerPlatform.instance = picker;
      debugAndroidStorageChoices = () async => const [
        (isRemovable: false, root: internalRoot),
        (isRemovable: true, root: sdRoot),
      ];
      debugCreateLibrarySetupBloc = () => bloc = _RecordingDownloadBloc();
    });
    tearDown(() {
      debugAndroidStorageChoices = null;
      debugCreateLibrarySetupBloc = null;
    });

    Finder inTile(String tileTitle, Finder matching) => find.descendant(
      of: find.ancestor(
        of: find.text(tileTitle),
        matching: find.byType(SettingsActionTile),
      ),
      matching: matching,
    );

    Future<void> tapUse(WidgetTester tester, String tileTitle) async {
      final button = inTile(tileTitle, find.byType(ActionButton));
      await tester.ensureVisible(button);
      tester.widget<ActionButton>(button).onPressed!();
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      _actionOnPressed(tester, 'אישור')!();
      await tester.pumpAndSettle();
    }

    testWidgets('אין בורר תיקיות חופשי, רק אחסון פנימי וכרטיס SD', (
      tester,
    ) async {
      await _openSetup(tester, defaultTargetPath: internalRoot);
      expect(find.text('בחירת מיקום'), findsNothing);
      expect(find.text('שנה מיקום'), findsNothing);
      expect(inTile('אחסון פנימי', find.text('נבחר')), findsOneWidget);
      expect(inTile('כרטיס SD', find.byType(ActionButton)), findsOneWidget);
      expect(picker.calls, 0);
    });

    testWidgets('בחירת כרטיס SD מעדכנת את היעד בלי לפתוח בורר', (
      tester,
    ) async {
      await _openSetup(tester, defaultTargetPath: internalRoot);
      await tapUse(tester, 'כרטיס SD');
      expect(inTile('כרטיס SD', find.text('נבחר')), findsOneWidget);
      expect(inTile('אחסון פנימי', find.byType(ActionButton)), findsOneWidget);
      expect(find.textContaining('ניקוי מטמון'), findsOneWidget);
      expect(picker.calls, 0);
    });

    testWidgets('אישור עם כרטיס SD: הורדה אל sdRoot/books ושמירת השורש', (
      tester,
    ) async {
      await _openSetup(tester, defaultTargetPath: internalRoot);
      await tapUse(tester, 'כרטיס SD');
      await confirm(tester);
      expect(bloc.targets, [p.join(sdRoot, 'books')]);
      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        sdRoot,
      );
    });

    testWidgets('אישור עם אחסון פנימי מנקה שורש SD שנשמר קודם', (
      tester,
    ) async {
      await Settings.setValue<String>(
        SettingsRepository.keyAndroidLibraryRoot,
        sdRoot,
      );
      await _openSetup(tester, defaultTargetPath: internalRoot);
      await confirm(tester);
      expect(bloc.targets, [p.join(internalRoot, 'books')]);
      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        '',
      );
    });

    for (final discovery in ['ממתין', 'נכשל', 'ללא הכרטיס']) {
      testWidgets('גילוי $discovery: התקנה לאותו SD שומרת את השורש', (
        tester,
      ) async {
        await Settings.setValue<String>(
          SettingsRepository.keyAndroidLibraryRoot,
          sdRoot,
        );
        debugAndroidStorageChoices = () => switch (discovery) {
          'ממתין' =>
            Completer<List<({bool isRemovable, String root})>>().future,
          'נכשל' => Future.error(StateError('גילוי האחסון נכשל')),
          _ => Future.value(const [(isRemovable: false, root: internalRoot)]),
        };
        await _openSetup(tester, defaultTargetPath: sdRoot);
        await confirm(tester);
        expect(bloc.targets, [p.join(sdRoot, 'books')]);
        expect(
          Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
          sdRoot,
        );
      });
    }

    testWidgets('בחירה מפורשת באחסון פנימי מנקה את שורש ה-SD בהצלחה', (
      tester,
    ) async {
      await Settings.setValue<String>(
        SettingsRepository.keyAndroidLibraryRoot,
        sdRoot,
      );
      await _openSetup(tester, defaultTargetPath: sdRoot);
      await tapUse(tester, 'אחסון פנימי');
      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        sdRoot,
      );
      await confirm(tester);
      expect(bloc.targets, [p.join(internalRoot, 'books')]);
      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        '',
      );
    });

    testWidgets('כשל התקנה אחרי בחירה פנימית אינו משנה את שורש ה-SD', (
      tester,
    ) async {
      await Settings.setValue<String>(
        SettingsRepository.keyAndroidLibraryRoot,
        sdRoot,
      );
      await _openSetup(tester, defaultTargetPath: sdRoot);
      await tapUse(tester, 'אחסון פנימי');
      bloc.completionState = const EmptyLibraryError(
        errorMessage: 'ההתקנה נכשלה',
      );
      await confirm(tester);
      expect(bloc.targets, [p.join(internalRoot, 'books')]);
      expect(find.text('ההתקנה נכשלה'), findsOneWidget);
      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        sdRoot,
      );
    });

    testWidgets('ביטול אחרי בחירת SD אינו שומר את הבחירה', (tester) async {
      await Settings.setValue<String>(
        SettingsRepository.keyAndroidLibraryRoot,
        '',
      );
      await _openSetup(tester, defaultTargetPath: internalRoot);
      await tapUse(tester, 'כרטיס SD');
      _actionOnPressed(tester, 'ביטול')!();
      await tester.pumpAndSettle();
      expect(bloc.targets, isEmpty);
      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        '',
      );
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

      // פריסת המקטע חושפת את אפשרויות ההחלפה.
      await _select(tester, 'החלפת הספרייה בספרייה אחרת');
      expect(find.text('הורדת הספרייה מחדש'), findsOneWidget);
      expect(find.text('בחירת תיקייה מהמחשב'), findsOneWidget);
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
        expect(find.text('בחר קובץ ספרייה'), findsNothing);
      },
    );
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
        final scan = await scanLibraryFolder(DirectoryPackageFolder(temp.path));
        expect(scan.readable, isFalse);
        expect(scan.found, isEmpty);
      },
    );

    test('scanLibraryFolder: קובץ קריא → זוהה', () async {
      final scan = await scanLibraryFolder(DirectoryPackageFolder(temp.path));
      expect(scan.readable, isTrue);
      expect(scan.found, contains(LibraryComponent.libraryDb));
    });

    test('scanLibraryFolder: lexical-v2.db מזוהה כמילון', () async {
      await File('${temp.path}/lexical-v2.db').writeAsBytes([3]);
      final scan = await scanLibraryFolder(DirectoryPackageFolder(temp.path));
      expect(scan.found, contains(LibraryComponent.lexicon));
    });

    test('scanLibraryFolder: קבצים בתת-התיקייה library_db מזוהים', () async {
      final sub = await Directory('${temp.path}/library_db').create();
      await File('${temp.path}/seforim.db').delete();
      await File('${sub.path}/seforim.db.zst').writeAsBytes([1]);
      final scan = await scanLibraryFolder(DirectoryPackageFolder(temp.path));
      expect(scan.found, {LibraryComponent.libraryDb});
    });

    testWidgets('תיקייה חסומה: הנחיה לבחור תיקייה אחרת, ואישור מושבת', (
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
      expect(find.text('בחר קובץ ספרייה'), findsNothing);
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });

    testWidgets('תיקייה קריאה: פירוט לפי רכיב ואישור פעיל', (tester) async {
      await _openSetup(tester);
      await _select(tester, 'בחירת תיקייה מהמחשב');
      await tester.ensureVisible(find.text('בחר תיקייה'));
      // הסריקה קוראת מהדיסק — IO אמיתי אינו מסתיים תחת FakeAsync.
      await tester.runAsync(() async {
        await tester.tap(find.text('בחר תיקייה'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('נמצאו קובצי הספרייה — הפירוט למטה'), findsOneWidget);
      expect(find.text('מה נמצא בתיקייה'), findsOneWidget);
      expect(find.text('ספריית הספרים (seforim.db)'), findsOneWidget);
      expect(find.text('ספרי התלמוד בבלי לא ייכללו'), findsOneWidget);
      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });
  });

  group('תיקיית קובצי הספרייה (כמו SAF באנדרואיד)', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('otzaria_raw_dialog_');
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
    });

    tearDown(() async {
      debugPickAndroidSourceFolder = null;
      debugCreateLibrarySetupBloc = null;
      EmptyLibraryBloc.tempRootOverride = null;
      await temp.delete(recursive: true);
    });

    Future<void> pickFolder(WidgetTester tester, PackageFolder folder) async {
      debugPickAndroidSourceFolder = () async => folder;
      await _openSetup(tester, defaultTargetPath: p.join(temp.path, 'lib'));
      await _select(tester, 'בחירת תיקייה מהמחשב');
      await tester.ensureVisible(find.text('בחר תיקייה'));
      await tester.runAsync(() async {
        await tester.tap(find.text('בחר תיקייה'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }

    final fullBundle = _MemoryFolder(
      'Download/otzaria',
      {DatabaseConstants.talmudBavliArchiveFileName: Uint8List(10)},
      children: {
        'library_db': _MemoryFolder('Download/otzaria/library_db', {
          DatabaseConstants.databaseArchiveFileName: Uint8List(10),
          DatabaseConstants.externalCatalogArchiveFileName: Uint8List(10),
          DatabaseConstants.lexicalDatabaseFileName: Uint8List(10),
        }),
      },
    );

    testWidgets('חבילת אנדרואיד המלאה: כל רכיב מוצג עם הקובץ שנמצא', (
      tester,
    ) async {
      await pickFolder(tester, fullBundle);

      for (final label in [
        'ספריית הספרים (seforim.db)',
        'תלמוד בבלי (קובצי PDF)',
        'קטלוג אוצר החכמה',
        'מילון לחיפוש מקורב',
        'אינדקס חיפוש',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
        find.text(DatabaseConstants.databaseArchiveFileName),
        findsOneWidget,
      );
      expect(
        find.text(DatabaseConstants.talmudBavliArchiveFileName),
        findsOneWidget,
      );
      expect(
        find.text('התוכנה תבנה את אינדקס החיפוש אחרי ההתקנה'),
        findsOneWidget,
      );
      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });

    /// חלקי ספרייה ומניפסט, כמו בכרכי ה-ZIP של חבילת אנדרואיד המלאה.
    Map<String, List<int>> splitLibrary() {
      final dir = Directory(p.join(temp.path, 'split'))..createSync();
      writeSplitAsset(
        dir,
        'otzaria-0.9.98-library.tar.zst',
        Uint8List(300),
        partSize: 100,
      );
      return {
        for (final file in dir.listSync().whereType<File>())
          p.basename(file.path): file.readAsBytesSync(),
      };
    }

    testWidgets('נבחר כרך אחד: הפניה לתיקייה שמכילה את כל הכרכים', (
      tester,
    ) async {
      const part = 'otzaria-0.9.98-library.tar.zst.part-001';
      final files = splitLibrary()..remove(part);
      await pickFolder(
        tester,
        _MemoryFolder(
          'otzaria-android-full-part1',
          const {},
          children: {
            'otzaria-android-full': _MemoryFolder('inner', files),
          },
        ),
      );
      expect(
        find.text(
          'חסר הקובץ $part — כנראה ששאר קובצי ה-ZIP חולצו לתיקיות שלצד התיקייה שנבחרה. יש לבחור את התיקייה שמכילה את כולן',
        ),
        findsOneWidget,
      );
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });

    testWidgets('אותו חלק בשני כרכים בגדלים שונים: הסבר ואישור מושבת', (
      tester,
    ) async {
      const part = 'otzaria-0.9.98-library.tar.zst.part-001';
      final files = splitLibrary();
      await pickFolder(
        tester,
        _MemoryFolder(
          'Download',
          const {},
          children: {
            'otzaria-android-full-part1': _MemoryFolder('v1', files),
            'otzaria-android-full-part2': _MemoryFolder('v2', {
              part: Uint8List(40),
            }),
          },
        ),
      );
      expect(
        find.text(
          'הקובץ $part נמצא בשתי תיקיות בגדלים שונים — יש למחוק את התיקיות שחולצו ולחלץ מחדש את כל קובצי ה-ZIP',
        ),
        findsOneWidget,
      );
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });

    testWidgets('בלי קובץ הספרייה: הסבר ברור ואישור מושבת', (tester) async {
      await pickFolder(
        tester,
        _MemoryFolder('x', {
          DatabaseConstants.lexicalDatabaseFileName: [1],
        }),
      );
      expect(
        find.textContaining('לא נמצא בתיקייה קובץ הספרייה'),
        findsOneWidget,
      );
      expect(find.text('חובה — בלעדיו לא ניתן להתקין'), findsOneWidget);
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });

    testWidgets('אחרי ההתקנה: סיכום מה הותקן ומה חסר, ואז הדיאלוג נסגר', (
      tester,
    ) async {
      EmptyLibraryBloc.tempRootOverride = temp.path;
      debugCreateLibrarySetupBloc = () => EmptyLibraryBloc(
        downloadSpaceChecker: (_) async => null,
        packageImporter: LibraryPackageImporter(
          rawRunner: (job, {required onProgress, required cancel}) =>
              extractRawAssetJob(
                job,
                openZstd: () => throw StateError('אין נכס דחוס'),
                onProgress: onProgress,
              ),
          diskSpace: (_) async => DiskSpaceInfo.unknown,
        ),
      );
      Future<void> pumpUntil(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      await pickFolder(
        tester,
        _MemoryFolder('x', {
          DatabaseConstants.databaseFileName: utf8.encode('db'),
          DatabaseConstants.lexicalDatabaseFileName: utf8.encode('lex'),
        }),
      );
      await tester.tap(find.text('אישור'));
      await pumpUntil(() => find.text('הספרייה הותקנה').evaluate().isNotEmpty);

      expect(find.text('הספרייה הותקנה'), findsOneWidget);
      expect(find.text('הותקנו'), findsOneWidget);
      expect(find.text('חסרים'), findsOneWidget);
      expect(find.text('ספריית הספרים (seforim.db)'), findsOneWidget);
      expect(find.text('אינדקס חיפוש'), findsNothing);
      expect(
        find.textContaining(DatabaseConstants.talmudBavliArchiveFileName),
        findsOneWidget,
      );
      expect(
        File(
          p.join(temp.path, 'lib', 'books', DatabaseConstants.databaseFileName),
        ).readAsStringSync(),
        'db',
      );

      await tester.tap(find.text('סגור'));
      await tester.pumpAndSettle();
      expect(find.text('הספרייה הותקנה'), findsNothing);
    });
  });

  group('קובצי מסייע ההורדה', () {
    late Directory temp;
    late Directory downloads;
    const library = 'otzaria-0.9.98-library.tar.zst';
    const index = 'otzaria-0.9.98-library-index.tar.zst';

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('otzaria_pkg_dialog_');
      downloads = await Directory(p.join(temp.path, 'downloads')).create();
      FilePickerPlatform.instance = _FolderFilePickerPlatform(downloads.path);
    });

    tearDown(() async {
      debugCreateLibrarySetupBloc = null;
      await temp.delete(recursive: true);
    });

    Future<void> pickDownloads(WidgetTester tester) async {
      await _openSetup(tester, defaultTargetPath: p.join(temp.path, 'lib'));
      await _select(tester, 'בחירת תיקייה מהמחשב');
      await tester.ensureVisible(find.text('בחר תיקייה'));
      await tester.runAsync(() async {
        await tester.tap(find.text('בחר תיקייה'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('חלקי ספרייה ואינדקס מזוהים, ואישור פעיל', (tester) async {
      writeSplitAsset(downloads, library, Uint8List(300), partSize: 100);
      writeSplitAsset(downloads, index, Uint8List(100), partSize: 100);
      await pickDownloads(tester);
      expect(
        find.text(
          'נמצאה ספרייה מקבצים שהורדו (גרסה 0.9.98), כולל אינדקס חיפוש מוכן',
        ),
        findsOneWidget,
      );
      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });

    testWidgets('חלק חסר: שם הקובץ מוצג ואישור מושבת', (tester) async {
      final names = writeSplitAsset(
        downloads,
        library,
        Uint8List(300),
        partSize: 100,
      );
      File(p.join(downloads.path, names[1])).deleteSync();
      await pickDownloads(tester);
      expect(
        find.text(
          'חסר הקובץ ${names[1]} — יש להכין את התיקייה מחדש במסייע ההורדה',
        ),
        findsOneWidget,
      );
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });

    testWidgets('בזמן הפריסה יש כפתור ביטול, והוא עוצר את הייבוא', (
      tester,
    ) async {
      writeSplitAsset(downloads, library, Uint8List(300), partSize: 100);
      final started = Completer<void>();
      Future<void> waitForCancel(
        PackageExtractionJob job, {
        required PackageExtractionProgress onProgress,
        required ZstdCancelFlag cancel,
      }) async {
        onProgress(LibraryPackageKind.library, 10, 300);
        started.complete();
        final cell = ffi.Pointer<ffi.Uint8>.fromAddress(cancel.address);
        while (cell.value == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        throw const LibraryImportCancelled();
      }

      debugCreateLibrarySetupBloc = () => EmptyLibraryBloc(
        downloadSpaceChecker: (_) async => null,
        packageImporter: LibraryPackageImporter(
          runner: waitForCancel,
          diskSpace: (_) async => DiskSpaceInfo.unknown,
        ),
      );
      // ה-bloc נוצר בתוך FakeAsync, וה-IO שלו אמיתי: מתחלפים בין השניים.
      Future<void> pumpUntil(bool Function() done) async {
        for (var i = 0; i < 200 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      await pickDownloads(tester);
      await tester.tap(find.text('אישור'));
      await pumpUntil(
        () => find.textContaining('מאמת ופורס').evaluate().isNotEmpty,
      );
      expect(started.isCompleted, isTrue);
      expect(find.textContaining('מאמת ופורס את הספרייה'), findsOneWidget);

      await tester.tap(find.text('ביטול'));
      await pumpUntil(
        () => find.textContaining('הייבוא בוטל').evaluate().isNotEmpty,
      );
      expect(find.textContaining('הייבוא בוטל'), findsOneWidget);
      expect(
        Directory(p.join(temp.path, 'lib', 'books.import')).existsSync(),
        isFalse,
      );
    });
  });
}
