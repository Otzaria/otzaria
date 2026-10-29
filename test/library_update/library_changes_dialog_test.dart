import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_dialog.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_store.dart';
import 'package:positioned_sliver_list/positioned_sliver_list.dart';

/// בצורה של build_release_notes ב-SeforimLibrary (library_update_announce.py).
String _notes(int version, int books) {
  final buffer = StringBuffer()
    ..write('# גרסת ספרייה $version\n\n**עדכון א\' חשון תשפ"ז**\n')
    ..write('\n## התווספו הספרים הבאים:\n');
  for (var i = 0; i < books; i++) {
    buffer.write('* ספרות/הלכה/ספר $i\n');
  }
  buffer
    ..write('\n## השתנו הספרים הבאים:\n')
    ..write(
      '* תנך/תורה/בראשית - שינוי מהדורה ל-מהדורה ב (שונה גם מיקומו/שמו)\n',
    );
  return buffer.toString();
}

LibraryChangesNote _note(String tag, String markdown) =>
    LibraryChangesNote(releaseTag: tag, markdown: markdown, path: '$tag.md');

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  group('parseLibraryChanges', () {
    test('כותרת, תאריך מודגש, סעיפים ופריטים', () {
      final lines = parseLibraryChanges(_note('v33-1', _notes(33, 2)));
      expect(lines.map((l) => l.kind), [
        LibraryChangesLineKind.title,
        LibraryChangesLineKind.subtitle,
        LibraryChangesLineKind.section,
        LibraryChangesLineKind.item,
        LibraryChangesLineKind.item,
        LibraryChangesLineKind.section,
        LibraryChangesLineKind.item,
      ]);
      expect(lines[0].text, 'גרסת ספרייה 33');
      expect(lines[1].text, 'עדכון א\' חשון תשפ"ז');
      expect(lines[3].text, 'ספרות/הלכה/ספר 0');
    });

    test('קובץ בלי כותרת מקבל כותרת לפי הגרסה', () {
      final lines = parseLibraryChanges(_note('v34-1', '* א\n'));
      expect(lines.first.kind, LibraryChangesLineKind.title);
      expect(lines.first.version, 34);
    });
  });

  test('filterLibraryChanges שומר כותרות של פריטים תואמים בלבד', () {
    final parsed = [
      parseLibraryChanges(_note('v34-1', _notes(34, 3))),
      parseLibraryChanges(_note('v33-1', _notes(33, 3))),
    ];
    final filtered = filterLibraryChanges(parsed, 'בראשית');
    expect(filtered.map((l) => l.text), [
      'גרסת ספרייה 34',
      'עדכון א\' חשון תשפ"ז',
      'השתנו הספרים הבאים:',
      'תנך/תורה/בראשית - שינוי מהדורה ל-מהדורה ב (שונה גם מיקומו/שמו)',
      'גרסת ספרייה 33',
      'עדכון א\' חשון תשפ"ז',
      'השתנו הספרים הבאים:',
      'תנך/תורה/בראשית - שינוי מהדורה ל-מהדורה ב (שונה גם מיקומו/שמו)',
    ]);
    expect(filterLibraryChanges(parsed, 'אין כזה'), isEmpty);
  });

  test('חיפוש עם " מוצא גרשיים עבריים (״ ו-׳׳)', () {
    final parsed = [
      parseLibraryChanges(
        _note(
          'v34-1',
          '# גרסת ספרייה 34\n* הלכה/שו\u05F4ע\n* הלכה/רמ\u05F3\u05F3א\n',
        ),
      ),
    ];
    expect(
      filterLibraryChanges(parsed, 'שו"ע').map((l) => l.text),
      contains('הלכה/שו\u05F4ע'),
    );
    expect(
      filterLibraryChanges(parsed, 'רמ"א').map((l) => l.text),
      contains('הלכה/רמ\u05F3\u05F3א'),
    );
  });

  testWidgets('RTL, רשימה ארוכה נגללת, חיפוש מסנן וסגירה', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showLibraryChangesDialog(context, [
                _note('v35-1', _notes(35, 6000)),
                _note('v34-1', _notes(34, 5)),
              ]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    // מעל הסף הפירוק רץ ב-isolate — בינתיים מוצג חיווי טעינה.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    expect(find.text('מה חדש בספרים'), findsOneWidget);
    expect(find.text('גרסת ספרייה 35'), findsOneWidget);
    final item = find.text('ספרות/הלכה/ספר 0');
    expect(item, findsOneWidget);
    expect(
      Directionality.of(tester.element(item)),
      TextDirection.rtl,
    );
    // ListView עצל: אלפי הפריטים אינם נבנים מראש.
    expect(find.text('ספרות/הלכה/ספר 5999'), findsNothing);

    await tester.dragUntilVisible(
      find.text('ספרות/הלכה/ספר 200'),
      find.byType(SuperListView),
      const Offset(0, -500),
    );
    expect(find.text('ספרות/הלכה/ספר 200'), findsOneWidget);
    expect(find.text('ספרות/הלכה/ספר 0'), findsNothing);

    await tester.enterText(find.byType(EditableText), 'ספר 5999');
    await tester.pump();
    expect(find.text('ספרות/הלכה/ספר 5999'), findsNothing);
    await tester.pump(LibraryChangesDialog.searchDebounce);
    await tester.pumpAndSettle();
    expect(find.text('ספרות/הלכה/ספר 5999'), findsOneWidget);
    expect(find.text('גרסת ספרייה 34'), findsNothing);

    await tester.tap(find.text('סגור'));
    await tester.pumpAndSettle();
    expect(find.text('מה חדש בספרים'), findsNothing);
  });

  testWidgets(
    'גרירת פס הגלילה בעכבר גוללת את הרשימה (issue #3321)',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showLibraryChangesDialog(context, [
                  _note('v35-1', _notes(35, 100)),
                ]),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      ScrollPosition position() => Scrollable.of(
        tester.element(find.text('• ספרות/הלכה/ספר 0')),
      ).position;
      final list = find.byType(SuperListView);
      final bar = tester.getRect(
        find.ancestor(of: list, matching: find.byType(Scrollbar)).first,
      );
      // ה-thumb בקצה הסוף של הרשימה (שמאל ב-RTL), ובראשה כל עוד לא נגללה.
      final rtl = Directionality.of(tester.element(list)) == TextDirection.rtl;
      final thumb = Offset(rtl ? bar.left + 4 : bar.right - 4, bar.top + 10);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: bar.center);

      Future<void> dragThumb() async {
        // ריחוף מעל הפס מציג אותו; בלי זה הוא שקוף ואינו נתפס.
        await mouse.moveTo(thumb);
        await tester.pumpAndSettle();
        await mouse.down(thumb);
        await tester.pump();
        await mouse.moveBy(const Offset(0, 100));
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();
      }

      final first = position();
      await dragThumb();
      expect(first.pixels, greaterThan(100));

      // סינון בונה רשימה חדשה (מפתח לכל סינון) שמתחברת לאותו בקר.
      await tester.enterText(find.byType(EditableText), 'ספרות');
      await tester.pump(LibraryChangesDialog.searchDebounce);
      await tester.pumpAndSettle();
      final filtered = position();
      expect(filtered, isNot(same(first)));
      expect(filtered.pixels, 0);
      await dragThumb();
      expect(filtered.pixels, greaterThan(100));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('קפיצה לסוף הרשימה לא בונה את כל השורות שבדרך (#3022)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showLibraryChangesDialog(context, [
                _note('v35-1', _notes(35, 6000)),
              ]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    final position = Scrollable.of(
      tester.element(find.text('ספרות/הלכה/ספר 0')),
    ).position;
    var builtLines = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget.runtimeType.toString() == '_LineView') builtLines++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // כמו גרירת ה-thumb לסוף: קפיצה רחוקה בפריים אחד.
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(builtLines, lessThan(200));
    expect(
      find.text(
        'תנך/תורה/בראשית - שינוי מהדורה ל-מהדורה ב (שונה גם מיקומו/שמו)',
      ),
      findsOneWidget,
    );
  });
}
