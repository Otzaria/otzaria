import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/tools/gematria/widgets/gematria_result_card.dart';

import '../../test_helpers/stub_settings_bloc.dart';

void main() {
  const result = GematriaSearchResult(
    bookTitle: 'בראשית',
    internalPath: 'בראשית, פרק א, פסוק א',
    preview: 'בראשית ברא אלהים',
    data: SearchResult(file: 'בראשית.txt', line: 1, text: 'בראשית ברא אלהים'),
  );

  Future<void> pumpCard(WidgetTester tester, int number, double textScale) {
    final bloc = StubSettingsBloc();
    addTearDown(bloc.close);
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: BlocProvider<SettingsBloc>.value(
            value: bloc,
            child: Scaffold(
              body: GematriaResultCard(number: number, result: result),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('בלי הגדלת טקסט תג המספר הוא ריבוע 26', (tester) async {
    await pumpCard(tester, 7, 1.0);

    final badge = find.ancestor(
      of: find.text('7'),
      matching: find.byType(Container),
    );
    expect(tester.getSize(badge.first), const Size(26, 26));
  });

  // אותה בעיה כמו תג הדירוג בחיפוש: תיבה בגודל קבוע חתכה
  // את הספרות בהגדלת טקסט, והגליף חרג מהעיגול.
  for (final scale in [1.5, 2.0]) {
    testWidgets('בהגדלת טקסט $scale תג המספר מכיל את הספרות', (tester) async {
      await pumpCard(tester, 128, scale);

      final digits = tester.widget<Text>(find.text('128'));
      final context = tester.element(find.text('128'));
      final painter = TextPainter(
        text: TextSpan(
          text: '128',
          style: DefaultTextStyle.of(context).style.merge(digits.style),
        ),
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.linear(scale),
      )..layout();
      addTearDown(painter.dispose);

      final badge = tester.getSize(
        find
            .ancestor(of: find.text('128'), matching: find.byType(Container))
            .first,
      );
      expect(badge.height, greaterThanOrEqualTo(painter.height));
      expect(badge.width, greaterThanOrEqualTo(painter.width));
    });
  }
}
