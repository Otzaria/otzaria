import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/widgets/commentary/commentary_search_results_list.dart';

import '../../helpers/memory_settings_cache.dart';

/// רשימת קטעי תוצאות החיפוש הייתה קיימת בכרטיסיית המפרשים בטקסט בלבד; ב-PDF
/// הוצג `SizedBox.shrink()`. הטסטים כאן נועלים את הרשימה המשותפת ואת המיפוי
/// בין היקרות (currentIdx) לשורה המסומנת.
class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

CommentarySearchSnippet _snippet(String path, String text, int globalIndex) =>
    CommentarySearchSnippet(
      path: path,
      snippet: text,
      globalIndex: globalIndex,
    );

Future<int?> _pump(
  WidgetTester tester, {
  required String query,
  required List<CommentarySearchSnippet> snippets,
  int currentIdx = 0,
}) async {
  int? tapped;
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: _FakeSettingsBloc(),
        child: Scaffold(
          body: CommentarySearchResultsList(
            query: query,
            snippets: snippets,
            currentIdx: currentIdx,
            onSnippetTap: (index) => tapped = index,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tapped;
}

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('resolveSelectedSnippetGlobalIndex', () {
    final snippets = [
      _snippet('a', 's1', 0),
      _snippet('b', 's2', 3),
    ];

    test('התאמה מדויקת ל-globalIndex', () {
      expect(resolveSelectedSnippetGlobalIndex(snippets, 0), 0);
      expect(resolveSelectedSnippetGlobalIndex(snippets, 3), 3);
    });

    test('היקרות בתוך אותו מפרש נשארת על שורתו', () {
      expect(resolveSelectedSnippetGlobalIndex(snippets, 1), 0);
      expect(resolveSelectedSnippetGlobalIndex(snippets, 2), 0);
      expect(resolveSelectedSnippetGlobalIndex(snippets, 4), 3);
    });

    test('רשימה ריקה מחזירה -1', () {
      expect(resolveSelectedSnippetGlobalIndex(const [], 0), -1);
    });

    test('אינדקס לפני הקטע הראשון מחזיר -1', () {
      expect(
        resolveSelectedSnippetGlobalIndex([_snippet('a', 's', 5)], 2),
        -1,
      );
    });
  });

  group('CommentarySearchResultsList — תצוגה', () {
    testWidgets('שאילתה ריקה אינה מציגה דבר', (tester) async {
      await _pump(tester, query: '', snippets: [_snippet('a', 'טקסט', 0)]);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('שאילתה ללא קטעים מציגה "טוען תוצאות..."', (tester) async {
      await _pump(tester, query: 'שבת', snippets: const []);
      expect(find.text('טוען תוצאות...'), findsOneWidget);
    });

    testWidgets('קטע מוצג עם כותרת המפרש', (tester) async {
      await _pump(
        tester,
        query: 'שבת',
        snippets: [_snippet('רש"י על שבת', 'ענין שבת', 0)],
      );
      expect(find.text('רש"י על שבת'), findsOneWidget);
    });

    testWidgets('קטעים מאותו מפרש מקבלים כותרת אחת', (tester) async {
      await _pump(
        tester,
        query: 'שבת',
        snippets: [
          _snippet('רש"י', 'קטע א', 0),
          _snippet('רש"י', 'קטע ב', 1),
        ],
      );
      expect(find.text('רש"י'), findsOneWidget);
    });

    testWidgets('שני מפרשים שונים מקבלים שתי כותרות', (tester) async {
      await _pump(
        tester,
        query: 'שבת',
        snippets: [
          _snippet('רש"י', 'קטע א', 0),
          _snippet('תוספות', 'קטע ב', 1),
        ],
      );
      expect(find.text('רש"י'), findsOneWidget);
      expect(find.text('תוספות'), findsOneWidget);
    });

    testWidgets('לחיצה על קטע מדווחת את ה-globalIndex שלו', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: _FakeSettingsBloc(),
            child: Scaffold(
              body: CommentarySearchResultsList(
                query: 'שבת',
                snippets: [
                  _snippet('רש"י', 'קטע א', 0),
                  _snippet('תוספות', 'קטע ב', 7),
                ],
                currentIdx: 0,
                onSnippetTap: (index) => tapped = index,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(InkWell).last);
      await tester.pump();
      expect(tapped, 7);
    });
  });

  group('מבנה — שני משטחי המפרשים צורכים את אותה רשימה', () {
    String read(String path) => File(path).readAsStringSync();

    test('כרטיסיית הטקסט וכרטיסיית ה-PDF מייבאות את הרשימה המשותפת', () {
      const importRef =
          'widgets/commentary/commentary_search_results_list.dart';
      expect(
        read('lib/text_book/view/commentators_tab_screen.dart'),
        contains(importRef),
      );
      expect(
        read('lib/pdf_book/view/pdf_commentators_tab_screen.dart'),
        contains(importRef),
      );
    });

    test('כרטיסיית ה-PDF אינה מציגה עוד placeholder ריק לתוצאות', () {
      expect(
        read('lib/pdf_book/view/pdf_commentators_tab_screen.dart'),
        isNot(contains('resultsWidget: const SizedBox.shrink()')),
      );
    });

    test('פאנל ה-PDF מפרסם קטעי חיפוש ויודע לנווט לאינדקס גלובלי', () {
      final source = read('lib/pdf_book/view/pdf_commentary_panel.dart');
      expect(source, contains('externalSearchSnippetsNotifier'));
      expect(source, contains('navigateToGlobalIndex'));
    });
  });
}
