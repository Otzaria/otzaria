import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/per_book_display_settings.dart';
import '../../helpers/memory_settings_cache.dart';

class _FakeSettingsBloc extends Fake implements SettingsBloc {
  _FakeSettingsBloc(this.state);

  @override
  final SettingsState state;
}

/// השמירה פר-ספר משווה מול ברירת המחדל האפקטיבית, כולל החרגות התנ"ך. בלעדיה
/// בחירה שסוטה מההחרגה נחשבת "כמו ברירת המחדל" ונעלמת בפתיחה הבאה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('per_book_display');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
  });

  tearDown(() async {
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final book = TextBook(title: 'בראשית', categoryId: 1);

  TextBookLoaded loaded({required bool isTanach}) => TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 25,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    isTanach: isTanach,
    removeNikud: false,
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: '',
  );

  /// מריץ את השמירה בתוך עץ ווידג'טים ומחזיר את מה שנכתב לקובץ.
  /// גישת הקבצים חייבת לרוץ ב-[WidgetTester.runAsync] — ה-async המדומה של
  /// testWidgets אינו מקדם I/O אמיתי, וההמתנה נתקעת.
  Future<Map<String, dynamic>?> saveAndRead(
    WidgetTester tester,
    SettingsState settings,
    TextBookLoaded state, {
    bool? removeNikud,
    bool? removePunctuation,
    bool? mikraTraditionalLayout,
  }) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      Provider<SettingsBloc>.value(
        value: _FakeSettingsBloc(settings),
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    Map<String, dynamic>? json;
    await tester.runAsync(() async {
      await savePerBookDisplaySettings(
        capturedContext,
        state,
        removeNikud: removeNikud,
        removePunctuation: removePunctuation,
        mikraTraditionalLayout: mikraTraditionalLayout,
      );
      json = await PerBookSettings.loadSettings(PerBookSettings.bookKey(book));
    });
    return json;
  }

  final tanachOnly = SettingsState.initial().copyWith(
    enablePerBookSettings: true,
    defaultRemoveNikud: true,
    removeNikudFromTanach: false,
  );

  testWidgets('הסתרת ניקוד בתנ"ך במצב "הצג ניקוד בתנ"ך" נשמרת', (tester) async {
    // הברירה האפקטיבית בתנ"ך היא false (פטור), ולכן true הוא override אמיתי.
    final json = await saveAndRead(
      tester,
      tanachOnly,
      loaded(isTanach: true),
      removeNikud: true,
    );

    expect(json?['display']['body.regular.display']['nikud'], 'hide');
    expect(json?['isTanach'], isNull, reason: 'ההחרגה חיה במדיניות, לא בקובץ');
  });

  testWidgets('הצגת ניקוד בתנ"ך שווה לברירה האפקטיבית ואינה נשמרת', (
    tester,
  ) async {
    final json = await saveAndRead(
      tester,
      tanachOnly,
      loaded(isTanach: true),
      removeNikud: false,
    );

    expect(json, isNull);
  });

  testWidgets('בספר שאינו תנ"ך הברירה האפקטיבית היא ההגדרה הגלובלית', (
    tester,
  ) async {
    final json = await saveAndRead(
      tester,
      tanachOnly,
      loaded(isTanach: false),
      removeNikud: true,
    );

    expect(json, isNull, reason: 'true שווה לברירת המחדל בספר שאינו תנ"ך');
  });

  testWidgets('override פיסוק בתנ"ך נשמר כטלאי על חריץ הגוף', (tester) async {
    final settings = SettingsState.initial().copyWith(
      enablePerBookSettings: true,
      defaultRemovePunctuation: true,
    );

    final json = await saveAndRead(
      tester,
      settings,
      loaded(isTanach: true),
      removePunctuation: true,
    );

    expect(json?['display']['body.regular.display']['punctuation'], 'hide');
    expect(json?['isTanach'], isNull);
  });

  testWidgets('כשההתאמות פר-ספר כבויות לא נשמר דבר', (tester) async {
    final settings = tanachOnly.copyWith(enablePerBookSettings: false);

    final json = await saveAndRead(
      tester,
      settings,
      loaded(isTanach: true),
      removeNikud: true,
    );

    expect(json, isNull);
  });
  group('תצוגת המקרא ברצף לכל ספר', () {
    final perBook = SettingsState.initial().copyWith(
      enablePerBookSettings: true,
      mikraTraditionalLayout: true,
    );

    testWidgets('"כנדפס" בספר, כשהכללית "כמסורה" — נשמר', (tester) async {
      final json = await saveAndRead(
        tester,
        perBook,
        loaded(isTanach: true),
        mikraTraditionalLayout: false,
      );
      expect(json?['mikraTraditionalLayout'], isFalse);
    });

    testWidgets('בחירה ששווה לכללית — לא נשמרת', (tester) async {
      final json = await saveAndRead(
        tester,
        perBook,
        loaded(isTanach: true),
        mikraTraditionalLayout: true,
      );
      expect(json, isNull);
    });

    testWidgets('שמירת הגדרה אחרת אינה מוחקת את בחירת המקרא', (tester) async {
      await saveAndRead(
        tester,
        perBook,
        loaded(isTanach: true),
        mikraTraditionalLayout: false,
      );
      final json = await saveAndRead(
        tester,
        perBook.copyWith(defaultRemoveNikud: false),
        loaded(isTanach: true),
        removeNikud: true,
      );
      expect(json?['mikraTraditionalLayout'], isFalse);
      expect(json?['display'], isNotNull);
    });

    testWidgets('חזרה לבחירה הכללית מוחקת את הבחירה מהקובץ', (tester) async {
      await saveAndRead(
        tester,
        perBook,
        loaded(isTanach: true),
        mikraTraditionalLayout: false,
      );
      final json = await saveAndRead(
        tester,
        perBook,
        loaded(isTanach: true),
        mikraTraditionalLayout: true,
      );
      expect(json, isNull);
    });

    test('JSON הלוך וחזור', () {
      final settings = TextBookPerBookSettings(mikraTraditionalLayout: false);
      final json = settings.toJson();
      expect(json['mikraTraditionalLayout'], isFalse);
      expect(
        TextBookPerBookSettings.fromJson(json).mikraTraditionalLayout,
        isFalse,
      );
      expect(TextBookPerBookSettings().toJson(), isEmpty);
    });
  });
}
