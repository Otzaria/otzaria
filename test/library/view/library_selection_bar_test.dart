import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library_book_selection.dart';
import 'package:otzaria/library/view/library_selection_bar.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

Future<void> _pumpBar(
  WidgetTester tester,
  LibraryBookSelection selection, {
  required double width,
  VoidCallback? onOpen,
}) {
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: LibrarySelectionBar(
              selection: selection,
              onOpen: onOpen ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  LibraryBookSelection selectionOf(int count) {
    final selection = LibraryBookSelection();
    for (var i = 0; i < count; i++) {
      selection.toggle(TextBook(title: 'ספר $i'));
    }
    return selection;
  }

  testWidgets('מוסתר כשאין בחירה, ומופיע ונעלם עם הבחירה', (tester) async {
    final selection = LibraryBookSelection();
    addTearDown(selection.dispose);
    await _pumpBar(tester, selection, width: 600);
    expect(find.text('פתח נבחרים'), findsNothing);

    selection.toggle(TextBook(title: 'אחד'));
    await tester.pump();
    expect(find.text('ספר אחד נבחר'), findsOneWidget);
    expect(find.text('פתח נבחרים'), findsOneWidget);

    selection.clear();
    await tester.pump();
    expect(find.text('פתח נבחרים'), findsNothing);
  });

  for (final width in [600.0, 300.0, 190.0]) {
    testWidgets('המספר והכפתורים נראים בלי גלישה ברוחב ${width.toInt()}', (
      tester,
    ) async {
      final selection = selectionOf(3);
      addTearDown(selection.dispose);
      var opened = 0;
      await _pumpBar(tester, selection, width: width, onOpen: () => opened++);

      expect(tester.takeException(), isNull);
      expect(find.text('3 ספרים נבחרו'), findsOneWidget);
      expect(find.text('ביטול בחירה'), findsOneWidget);

      // כל הכפתורים בתוך הרוחב שהוקצה לסרגל, לא חתוכים בקצה.
      final bar = tester.getRect(find.byType(LibrarySelectionBar));
      for (final label in ['3 ספרים נבחרו', 'ביטול בחירה', 'פתח נבחרים']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(bar.left), reason: label);
        expect(rect.right, lessThanOrEqualTo(bar.right), reason: label);
      }

      await tester.tap(find.text('פתח נבחרים'));
      expect(opened, 1);

      await tester.tap(find.text('ביטול בחירה'));
      await tester.pump();
      expect(selection.isEmpty, isTrue);
    });
  }
}
