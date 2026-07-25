import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';

import '../support/search_engine_test_init.dart';

/// חיבור טקסטי המקטעים — כפי שנשמר ל-ref.
String _joined(List<SearchTitleSegment> segments) =>
    segments.map((segment) => segment.text).join();

Future<void> main() async {
  // buildSearchTitleSegments מפצל מילים דרך מנוע ה-Rust; מדולג כשאין build.
  final engineReady = await tryInitSearchEngine();

  group('buildSearchTitleSegments — מקטעי כותרת פריט חיפוש', () {
    test(
      'שאילתה פשוטה: מילים ומפרידים בלבד, ללא מקטעי אפשרויות',
      () {
        final segments = buildSearchTitleSegments(query: 'כדאי הוא בית');
        expect(_joined(segments), 'כדאי + הוא + בית');
        expect(segments.every((segment) => !segment.isOption), isTrue);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'אפשרויות רגילות מקוצרות למקטע אפשרות לפני/אחרי המילה',
      () {
        final segments = buildSearchTitleSegments(
          query: 'שלום',
          effectiveOptions: {
            'שלום_0': {'קידומות דקדוקיות': true, 'סיומות דקדוקיות': true},
          },
        );
        expect(_joined(segments), '(קד)שלום(סד)');
        expect(
          segments.where((segment) => segment.isOption).map((s) => s.text),
          ['(קד)', '(סד)'],
        );
        expect(
          segments.firstWhere((segment) => !segment.isOption).text,
          'שלום',
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'אפשרות מתקדמת ללא קיצור מוצגת בשמה המלא כמקטע אפשרות',
      () {
        final segments = buildSearchTitleSegments(
          query: 'שלום',
          effectiveOptions: {
            'שלום_0': {'תרגום ארמי': true},
          },
        );
        expect(_joined(segments), '(תרגום ארמי)שלום');
        expect(
          segments.singleWhere((segment) => segment.isOption).text,
          '(תרגום ארמי)',
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'מילים חלופיות, מרווח מותאם וטקסט שלילה — מקטעי מבנה (לא אפשרויות)',
      () {
        final segments = buildSearchTitleSegments(
          query: 'אב גד',
          alternativeWords: {
            0: ['אבא'],
          },
          spacingValues: {'0-1': '3'},
          negativeText: 'הס',
        );
        expect(_joined(segments), 'אב או אבא +3 גד ללא הס');
        expect(segments.every((segment) => !segment.isOption), isTrue);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });
}
