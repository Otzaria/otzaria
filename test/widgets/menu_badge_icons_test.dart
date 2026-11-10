import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_icon.dart';
import 'package:otzaria/widgets/misc/menu_badge_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// אותיות, וקישורים עם תג בעיגול. `link_24` (בלי תג) ו-`links` אינם כאלה.
bool _isLetterOrLinkName(String name) =>
    name.startsWith('alef_') ||
    name.startsWith('beit') ||
    name.startsWith('tet') ||
    (name.startsWith('link_') && !name.startsWith('link_24_'));

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

  test('אייקון שאינו אות או קישור עם תג אינו ברשימה', () {
    final wrong = <String>[
      for (final entry in OtzariaIcons.allIcons.entries)
        if (!_isLetterOrLinkName(entry.key) && isLetterOrLinkIcon(entry.value))
          entry.key,
    ];
    expect(wrong, isEmpty);
  });

  testWidgets('אייקון קישור עם תג מוגדל בתוך תא בגודל הרגיל', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: AppMenuIcon(OtzariaIcons.link_copy_24_regular, size: 18),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppMenuIcon)), const Size(18, 18));
    expect(tester.widget<Icon>(find.byType(Icon)).size, 24);
  });

  testWidgets('קישור בלי תג ו-links נשארים בגודל הרגיל (issue #3707)', (
    tester,
  ) async {
    for (final icon in [
      OtzariaIcons.link_24_regular,
      OtzariaIcons.link_24_filled,
      OtzariaIcons.links_24_regular,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: AppMenuIcon(icon, size: 18)),
        ),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).size, 18);
    }
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

  group('"קישור" בשורת האייקונים של הקליק הימני (issue #3871)', () {
    Future<void> rightClick(
      WidgetTester tester,
      List<AppContextMenuEntry> Function(BuildContext context) entries,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppContextMenuRegion(
                menuBuilder: (context, _) => entries(context),
                child: const SizedBox.square(dimension: 100),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(AppContextMenuRegion));
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await mouse.addPointer(location: center);
      addTearDown(mouse.removePointer);
      await mouse.down(center);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
    }

    // בשורה: קישור בלי תג, בגודל של השכנים. בתת-התפריט: הקישורים עם התג, מוגדלים.
    Future<void> expectLinkIcons(WidgetTester tester) async {
      Size sizeOf(IconData icon) => tester.getSize(find.byIcon(icon));
      for (final icon in [
        FluentIcons.library_24_regular,
        FluentIcons.copy_24_regular,
        FluentIcons.note_add_24_regular,
        OtzariaIcons.link_24_regular,
      ]) {
        expect(sizeOf(icon), const Size(18, 18), reason: '$icon');
      }

      await tester.tap(find.text('קישור'));
      await tester.pumpAndSettle();
      for (final icon in [
        OtzariaIcons.link_document_24_regular,
        OtzariaIcons.link_marker_24_regular,
        OtzariaIcons.link_alef_24_regular,
      ]) {
        expect(sizeOf(icon), const Size(24, 24), reason: '$icon');
      }
    }

    testWidgets('בטקסט הראשי', (tester) async {
      await rightClick(
        tester,
        (context) => [
          buildReaderIconRow(
            context: context,
            selection: ReaderMenuSelection('שלום'),
            book: TextBook(title: 'ספר בדיקה', id: 7),
            paragraphIndex: 0,
            selectedText: 'שלום',
            onCopy: () {},
            onAddNote: () {},
          ),
        ],
      );
      await expectLinkIcons(tester);
    });

    testWidgets('במפרשים (טקסט ו-PDF)', (tester) async {
      await rightClick(
        tester,
        (context) => ContextMenuUtils.buildCommentaryContextMenu(
          context: context,
          link: Link(
            heRef: 'רש"י פסוק א',
            index1: 12,
            path2: 'רש"י על שבת',
            index2: 5,
            connectionType: 'COMMENTARY',
            targetBookId: 9,
          ),
          openBookCallback: (_) {},
          fontSize: 16,
          displayProfile: TextDisplayProfile.defaults,
          savedSelectedText: 'שלום',
          onCopySelected: () {},
        ),
      );
      await expectLinkIcons(tester);
    });
  });
}
