import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_menu_icon.dart';
import 'package:otzaria/widgets/misc/menu_badge_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

bool _isLetterOrLinkName(String name) =>
    name.startsWith('alef_') ||
    name.startsWith('beit') ||
    name.startsWith('tet') ||
    name.startsWith('link');

void main() {
  test('כל אייקון אות וקישור של הספרייה נמצא ברשימה', () {
    final missing = <String>[
      for (final entry in OtzariaIcons.allIcons.entries)
        if (_isLetterOrLinkName(entry.key) && !isLetterOrLinkIcon(entry.value))
          entry.key,
    ];
    expect(
      missing,
      isEmpty,
      reason: 'אייקון שנוסף לספרייה חייב להתווסף ל-menu_badge_icons.dart',
    );
  });

  test('אייקון שאינו אות או קישור אינו ברשימה', () {
    final wrong = <String>[
      for (final entry in OtzariaIcons.allIcons.entries)
        if (!_isLetterOrLinkName(entry.key) && isLetterOrLinkIcon(entry.value))
          entry.key,
    ];
    expect(wrong, isEmpty);
  });

  testWidgets('אייקון קישור מוגדל בתוך תא בגודל הרגיל', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: AppMenuIcon(OtzariaIcons.link_24_regular, size: 18),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppMenuIcon)), const Size(18, 18));
    expect(tester.widget<Icon>(find.byType(Icon)).size, 24);
  });

  testWidgets('אייקון רגיל נשאר בגודלו', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: AppMenuIcon(OtzariaIcons.book_24_regular, size: 18),
        ),
      ),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).size, 18);
  });
}
