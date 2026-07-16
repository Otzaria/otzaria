import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

Future<void> main() async {
  // הקוד הנבדק קורא ל-sanitizeQuery/splitQueryWords שמאצילים למנוע ה-Rust;
  // הטסטים המסומנים מדולגים כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  group('PdfBookSearchView.computeTargetVisualIndexForTesting', () {
    test('תוצאות ריקות מחזירות 0', () {
      expect(
        PdfBookSearchView.computeTargetVisualIndexForTesting(
          resultsPageNumbersSorted: const [],
          currentPage: 5,
        ),
        0,
      );
    });

    test('עמוד נוכחי לפני כל התוצאות → כותרת העמוד הראשון', () {
      // עמודים בתוצאות: 5 (×2), 10 (×1). מבנה ויזואלי:
      // 0: כותרת עמוד 5
      // 1: תוצאה
      // 2: תוצאה
      // 3: כותרת עמוד 10
      // 4: תוצאה
      // עמוד נוכחי = 1 → היעד = עמוד 5 → אינדקס 0.
      expect(
        PdfBookSearchView.computeTargetVisualIndexForTesting(
          resultsPageNumbersSorted: const [5, 5, 10],
          currentPage: 1,
        ),
        0,
      );
    });

    test('עמוד נוכחי באמצע → כותרת העמוד הבא או שווה', () {
      // עמודים: 5, 10, 15. currentPage = 7 → היעד = 10.
      // מבנה: [hdr5, r, hdr10, r, hdr15, r]. אינדקס של hdr10 = 2.
      expect(
        PdfBookSearchView.computeTargetVisualIndexForTesting(
          resultsPageNumbersSorted: const [5, 10, 15],
          currentPage: 7,
        ),
        2,
      );
    });

    test('עמוד נוכחי שווה לעמוד בתוצאות → אותו עמוד', () {
      // currentPage = 10 → היעד = 10. אינדקס hdr10 = 2 (כמו למעלה).
      expect(
        PdfBookSearchView.computeTargetVisualIndexForTesting(
          resultsPageNumbersSorted: const [5, 10, 15],
          currentPage: 10,
        ),
        2,
      );
    });

    test(
        'באג P1: עמוד נוכחי אחרי כל התוצאות → fallback לעמוד האחרון, לא הראשון',
        () {
      // עמודים: 5, 10, 15. currentPage = 100 → אין עמוד >= 100.
      // fallback צריך להיות העמוד האחרון (15), לא הראשון (5).
      // מבנה: [hdr5, r, hdr10, r, hdr15, r]. אינדקס hdr15 = 4.
      expect(
        PdfBookSearchView.computeTargetVisualIndexForTesting(
          resultsPageNumbersSorted: const [5, 10, 15],
          currentPage: 100,
        ),
        4,
        reason: 'fallback אמור להיות העמוד האחרון, לא הראשון',
      );
    });

    test('עמוד אחד עם הרבה תוצאות', () {
      // 5 תוצאות באותו עמוד. currentPage = 7 → אין עמוד >= 7 → fallback ל-5.
      // מבנה: [hdr5, r, r, r, r, r]. היעד = hdr5 → אינדקס 0.
      expect(
        PdfBookSearchView.computeTargetVisualIndexForTesting(
          resultsPageNumbersSorted: const [5, 5, 5, 5, 5],
          currentPage: 7,
        ),
        0,
      );
    });

    test('כמה תוצאות בעמוד יעד → קופצים לכותרת, לא לתוצאה הראשונה', () {
      // עמודים: 5 (×3), 10 (×2). currentPage = 7 → היעד = 10.
      // מבנה: [hdr5, r, r, r, hdr10, r, r]. אינדקס hdr10 = 4.
      expect(
        PdfBookSearchView.computeTargetVisualIndexForTesting(
          resultsPageNumbersSorted: const [5, 5, 5, 10, 10],
          currentPage: 7,
        ),
        4,
      );
    });
  });

  group('SearchResultTile', () {
    late MockSettingsBloc settingsBloc;

    setUp(() {
      settingsBloc = MockSettingsBloc();
      whenListen(
        settingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial(),
      );
    });

    tearDown(() async {
      await settingsBloc.close();
    });

    testWidgets('מדגיש טקסט רגיל בחיפוש PDF פשוט', (tester) async {
      await tester.pumpWidget(_buildTile(
        settingsBloc: settingsBloc,
        text: 'שלום עולם',
        query: 'שלום',
        isSimpleSearch: true,
      ));

      expect(_highlightedText(tester), 'שלום');
    }, skip: !engineReady);

    testWidgets('מכבד HTML מודגש מתוצאות מנוע החיפוש', (tester) async {
      await tester.pumpWidget(_buildTile(
        settingsBloc: settingsBloc,
        text: '<font color="red">שלום</font> עולם',
        query: 'שלום',
        isSimpleSearch: false,
      ));

      expect(_highlightedText(tester), 'שלום');
    });
  });
}

Widget _buildTile({
  required SettingsBloc settingsBloc,
  required String text,
  required String query,
  required bool isSimpleSearch,
}) {
  return MaterialApp(
    home: BlocProvider<SettingsBloc>.value(
      value: settingsBloc,
      child: Scaffold(
        body: SearchResultTile(
          result: SearchResult(
              id: BigInt.one,
              title: 'ספר',
              reference: 'עמוד א',
              text: text,
              segment: BigInt.zero,
              isPdf: true,
              filePath: 'book.pdf',
              mergedCount: 1,
              merged: const []),
          onTap: () {},
          height: 50,
          query: query,
          isSimpleSearch: isSimpleSearch,
        ),
      ),
    ),
  );
}

String _highlightedText(WidgetTester tester) {
  final richText = tester.widgetList<RichText>(find.byType(RichText)).last;
  final spans = <TextSpan>[];

  void collect(InlineSpan span) {
    if (span is! TextSpan) return;
    spans.add(span);
    for (final child in span.children ?? const <InlineSpan>[]) {
      collect(child);
    }
  }

  collect(richText.text);
  return spans
      .where((span) => span.style?.fontWeight == FontWeight.bold)
      .map((span) => span.text ?? '')
      .join();
}
