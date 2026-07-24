import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/library_daf_yomi.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  TextButton buttonForIcon(WidgetTester tester, IconData icon) {
    return tester.widget<TextButton>(
      find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(TextButton),
      ),
    );
  }

  group('LibraryDafYomi — השבתת הדף היומי', () {
    testWidgets('dafEnabled=true — כפתור הדף היומי פעיל', (tester) async {
      await tester.pumpWidget(wrap(LibraryDafYomi(onDafYomiTap: (_, _) {})));

      expect(
        buttonForIcon(tester, FluentIcons.book_24_regular).onPressed,
        isNotNull,
      );
    });

    testWidgets('dafEnabled=false — הדף היומי מושבת, התאריך נשאר פעיל', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(LibraryDafYomi(dafEnabled: false, onDafYomiTap: (_, _) {})),
      );

      expect(
        buttonForIcon(tester, FluentIcons.book_24_regular).onPressed,
        isNull,
      );
      expect(
        buttonForIcon(tester, FluentIcons.calendar_24_regular).onPressed,
        isNotNull,
      );
    });
  });
}
