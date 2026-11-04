import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/panels/hidden_books_panel.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

Library _library() {
  final tora = Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [
      TextBook(title: 'בראשית', categoryId: 10),
      TextBook(title: 'שמות', categoryId: 10),
    ],
    parent: null,
  );
  final library = Library(categories: [tora]);
  tora.parent = library;
  return library;
}

String _key(String title) =>
    PerBookSettings.bookKey(TextBook(title: title, categoryId: 10));

Library _nestedLibrary() {
  final library = _library();
  final parent = library.subCategories.single;
  final child = Category(
    title: 'פרשות',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [TextBook(title: 'ויקרא', categoryId: 11)],
    parent: parent,
  );
  parent.subCategories.add(child);
  return library;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _TestLibraryBloc libraryBloc;
  late _MemoryCacheProvider cache;
  final droppedFromIndex = <String>[];
  final addedToIndex = <String>[];

  setUp(() async {
    cache = _MemoryCacheProvider();
    await Settings.init(cacheProvider: cache);
    tempDir = await Directory.systemTemp.createTemp('hidden_books_panel');
    droppedFromIndex.clear();
    addedToIndex.clear();
    libraryBloc = _TestLibraryBloc();
  });

  tearDown(() async {
    UiSnack.hide();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<String?> Function()? pickFile,
    Future<Library> Function()? libraryLoader,
    bool showSnacks = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      BlocProvider<LibraryBloc>.value(
        value: libraryBloc,
        child: MaterialApp(
          navigatorKey: showSnacks ? navigatorKey : null,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: HiddenBooksPanel(
                  pickFileOverride: pickFile,
                  libraryLoader: libraryLoader ?? () async => _library(),
                  indexDropper: (books) async {
                    droppedFromIndex.addAll(books.map((b) => b.title));
                    return true;
                  },
                  indexAdder: (books, _) {
                    addedToIndex.addAll(books.map((b) => b.title));
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('בחירת ספר מהרשימה מסתירה אותו (issue #1448)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();

    expect(find.text('בחירת ספרים וקטגוריות להסתרה'), findsWidgets);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().bookKeys, {_key('בראשית')});
    expect(droppedFromIndex, ['בראשית']);
  });

  testWidgets('פאנל פתוח קורא בחירה חדשה מהחנות לפני פעולת משתמש', (
    tester,
  ) async {
    await pump(tester);
    await const HiddenLibraryStore().save(
      HiddenLibrarySelection(bookKeys: {_key('בראשית')}),
    );

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .value,
      isTrue,
    );
  });

  testWidgets('שמירה מחלון אחר מתעדכנת בפאנל פתוח', (tester) async {
    await pump(tester);
    await const HiddenLibraryStore().save(
      HiddenLibrarySelection(bookKeys: {_key('בראשית')}),
    );
    await tester.pump();

    expect(find.text('בחירות הסתרה ישירות: 1'), findsOneWidget);
  });

  testWidgets('הסתרה מרעננת את עץ הספרייה מיד (issue #1448)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(
      libraryBloc.addedEvents.whereType<HiddenBooksChanged>(),
      hasLength(1),
      reason: 'בלעדיו ההסתרה נכנסת לתוקף רק בהפעלה הבאה',
    );
  });

  testWidgets('ביטול בדיאלוג הבחירה אינו משנה דבר (issue #1448)', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().isEmpty, isTrue);
    expect(droppedFromIndex, isEmpty);
  });

  testWidgets('אין הסתרות — מוצג הסבר ולא רשימה (issue #1448)', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('אין בחירות הסתרה'), findsOneWidget);
    expect(
      find.text('הצג רשימה'),
      findsNothing,
      reason: 'אין מה להציג, ולכן אין כפתור לחלון',
    );
  });

  testWidgets('ייבוא CSV מסתיר ושומר (issue #1448)', (tester) async {
    final file = File('${tempDir.path}/hide.csv')
      ..writeAsStringSync('בראשית\nאין כזה\n');

    await pump(tester, pickFile: () async => file.path);
    // הייבוא קורא קובץ אמיתי; pumpAndSettle מריץ פריימים ואינו ממתין ל-IO.
    await tester.runAsync(() async {
      await tester.tap(find.text('בחר קובץ'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(
      const HiddenLibraryStore().load().bookKeys,
      {_key('בראשית')},
      reason: 'רק השם שהותאם נשמר',
    );
    expect(find.text('בחירות הסתרה ישירות: 1'), findsOneWidget);
  });

  testWidgets('ספר שהוסתר יורד מאינדקס החיפוש (issue #1448)', (tester) async {
    final file = File('${tempDir.path}/hide.csv')..writeAsStringSync('שמות\n');

    await pump(tester, pickFile: () async => file.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('בחר קובץ'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(
      droppedFromIndex,
      ['שמות'],
      reason: 'הסרה מהאינדקס ולא סינון תוצאות — כך המונה נשאר נכון',
    );
  });

  testWidgets('כשל בכתיבת קטגוריות עדיין מנקה ספר שנשמר חלקית', (
    tester,
  ) async {
    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(categoryPaths: {'/לא קיימת'}),
    );
    cache.failCategoryWrites = true;
    final file = File('${tempDir.path}/partial.csv')
      ..writeAsStringSync('בראשית\n');
    await pump(tester, pickFile: () async => file.path, showSnacks: true);
    await tester.runAsync(() async {
      await tester.tap(find.text('בחר קובץ'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().bookKeys, {_key('בראשית')});
    expect(const HiddenLibraryStore().load().categoryPaths, {'/לא קיימת'});
    expect(droppedFromIndex, ['בראשית']);
    expect(
      libraryBloc.addedEvents.whereType<HiddenBooksChanged>(),
      hasLength(1),
    );
    expect(
      find.text(SettingsMessages.hiddenBooksSelectionSaveFailed),
      findsOneWidget,
    );
    expect(find.text(SettingsMessages.hiddenBooksImported(1, 0)), findsNothing);
    UiSnack.hide();
  });

  testWidgets('כשל בשמירת סמן האינדקס מונע שמירת בחירה', (tester) async {
    cache.failMarkerWrites = true;
    await pump(tester, showSnacks: true);
    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().isEmpty, isTrue);
    expect(droppedFromIndex, isEmpty);
    expect(
      find.text(SettingsMessages.hiddenBooksSelectionSaveFailed),
      findsOneWidget,
    );
    UiSnack.hide();
  });

  testWidgets('ביטול הסתרה מתוך החלון (issue #1448)', (tester) async {
    await const HiddenLibraryStore().save(
      HiddenLibrarySelection(bookKeys: {_key('שמות')}),
    );

    await pump(tester);
    expect(find.text('בחירות הסתרה ישירות: 1'), findsOneWidget);

    await tester.tap(find.text('הצג רשימה'));
    await tester.pumpAndSettle();
    expect(find.text('שמות'), findsOneWidget);

    await tester.tap(find.text('בטל הסתרה').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().isEmpty, isTrue);
    expect(find.text('אין בחירות הסתרה'), findsOneWidget);
    expect(addedToIndex, ['שמות']);
  });

  testWidgets('קטגוריה מוסתרת מוצגת בחלון לפי הנתיב (issue #1448)', (
    tester,
  ) async {
    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(categoryPaths: {'/תנ"ך/תורה'}),
    );

    await pump(tester);
    await tester.tap(find.text('הצג רשימה'));
    await tester.pumpAndSettle();

    expect(find.text('/תנ"ך/תורה'), findsOneWidget);
  });

  testWidgets('חיפוש, הסתרה וביטול הסתרה של קטגוריה וצאצאיה', (tester) async {
    await pump(tester, libraryLoader: () async => _nestedLibrary());

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('קטגוריות'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(RtlTextField), 'תורה');
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text('/תורה/פרשות'), findsOneWidget);
    final parentRow = find.ancestor(
      of: find.text('/תורה'),
      matching: find.byType(CheckboxListTile),
    );
    await tester.tap(parentRow);
    await tester.pumpAndSettle();
    final childRow = find.ancestor(
      of: find.text('/תורה/פרשות'),
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(childRow).value, isTrue);
    expect(tester.widget<CheckboxListTile>(childRow).onChanged, isNull);
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().categoryPaths, {'/תורה'});
    expect(const HiddenLibraryStore().load().bookKeys, isEmpty);
    expect(droppedFromIndex, ['בראשית', 'שמות', 'ויקרא']);
    expect(
      libraryBloc.addedEvents.whereType<HiddenBooksChanged>(),
      hasLength(1),
    );
    expect(find.text('בחירות הסתרה ישירות: 1'), findsOneWidget);

    await tester.tap(find.text('הצג רשימה'));
    await tester.pumpAndSettle();
    expect(find.text('בחירות הסתרה ישירות'), findsOneWidget);
    expect(find.text('/תורה'), findsOneWidget);
    expect(find.text('/תורה/פרשות'), findsNothing);
    expect(
      find.text(
        'הרשימה מציגה בחירות ישירות. להסרת הסתרה בירושה, בטלו את הסתרת קטגוריית האב.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('סגור'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הצג רק מוסתרים'));
    await tester.pumpAndSettle();
    expect(find.text('בחירות ישירות: 0'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    for (final tile in tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    )) {
      expect(tile.value, isTrue);
      expect(tile.onChanged, isNull);
    }
    expect(find.text('מוסתר דרך /תורה'), findsNWidgets(3));

    await tester.tap(find.text('קטגוריות'));
    await tester.pumpAndSettle();
    expect(find.text('בחירות ישירות: 1'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    final inheritedRow = find.ancestor(
      of: find.text('/תורה/פרשות'),
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(inheritedRow).value, isTrue);
    expect(tester.widget<CheckboxListTile>(inheritedRow).onChanged, isNull);
    await tester.tap(
      find.ancestor(
        of: find.text('/תורה'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().isEmpty, isTrue);
    expect(addedToIndex, ['בראשית', 'שמות', 'ויקרא']);
    expect(
      libraryBloc.addedEvents.whereType<HiddenBooksChanged>(),
      hasLength(2),
    );
  });

  testWidgets('מעבר בין ספרים לקטגוריות מסנן את הרשימה שנפתחת', (
    tester,
  ) async {
    await pump(tester, libraryLoader: () async => _nestedLibrary());
    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('הצג רק מוסתרים'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('קטגוריות'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.tap(find.text('הצג את כל הקטגוריות'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('/תורה/פרשות'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('הצג רק מוסתרים'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);

    await tester.tap(find.text('ספרים'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.text('ויקרא'), findsOneWidget);
    expect(find.text('מוסתר דרך /תורה/פרשות'), findsOneWidget);
  });

  testWidgets('הרשימה אינה מוצגת בגוף מסך ההגדרות (issue #1448)', (
    tester,
  ) async {
    await const HiddenLibraryStore().save(
      HiddenLibrarySelection(bookKeys: {_key('שמות')}),
    );

    await pump(tester);

    expect(
      find.text('שמות'),
      findsNothing,
      reason: 'מספר ההסתרות אינו חסום — רשימה פנימית הייתה מאריכה את המסך',
    );
  });

  testWidgets('קפיצה לסוף רשימה ארוכה בונה רק שורות נראות (issue #2381)', (
    tester,
  ) async {
    final library = _library();
    library.subCategories.single.books.addAll(
      List.generate(3000, (i) => TextBook(title: 'ספר $i', categoryId: 10)),
    );
    await pump(tester, libraryLoader: () async => library);
    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();

    var built = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is CheckboxListTile) built++;
    };
    final scroll = tester.widget<ListView>(find.byType(ListView).last);
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pump();
    debugOnRebuildDirtyWidget = null;

    expect(built, lessThan(50), reason: 'קפיצת פס הגלילה בנתה את כל הספרים');
    expect(find.text('ספר 2999'), findsOneWidget);
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};
  bool failCategoryWrites = false;
  bool failMarkerWrites = false;

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    if (failCategoryWrites && key == HiddenLibraryStore.categoryPathsSetting) {
      throw StateError('second write failed');
    }
    if (failMarkerWrites &&
        key == HiddenLibraryStore.pendingVisibilityIndexSetting) {
      throw StateError('marker write failed');
    }
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}

class _TestLibraryBloc extends Cubit<LibraryState> implements LibraryBloc {
  _TestLibraryBloc() : super(LibraryState.initial());

  final List<LibraryEvent> addedEvents = [];

  @override
  void add(LibraryEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
