import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_personal_notes_bloc.dart';
import '../test_helpers/stub_settings_bloc.dart';

// חלונית ניווט נעוצה בכרטיסיית המפרשים של ספר PDF, בחלון צר: היא שכבה עם
// הצללה. הקשה על ההצללה, Esc וכפתור הניווט סוגרים רק את השכבה; הנעיצה נשמרת,
// והחלונית נפתחת שוב מעצמה כשהחלון מתרחב (סעיף 11, החלטת הבעלים ג).

const _wide = Size(1100, 700);
const _narrow = Size(560, 700);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<void> pumpPinned(WidgetTester tester) async {
    tester.view.physicalSize = _wide;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 1,
    );
    addTearDown(sourceTab.dispose);
    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {'פרק א': 1, 'פרק ב': 10},
    );
    sourceTab.currentTitle.value = 'פרק א';
    final tab = PdfCommentatorsTab(sourceTab: sourceTab);
    final settings = StubSettingsBloc();
    final notes = StubPersonalNotesBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.close();
      await notes.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
          ],
          child: Scaffold(body: PdfCommentatorsTabScreen(tab: tab)),
        ),
      ),
    );
    await tester.pump();
    if (!_paneOpen(tester)) {
      await tester.tap(find.byType(NavPanelToggleButton));
      await _settle(tester);
    }
    await tester.tap(find.byTooltip('נעץ את החלונית'));
    await _settle(tester);
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await _settle(tester);
  }

  // ההצללה מכסה את הצד הרחוק מהחלונית (החלונית בימין).
  Future<void> tapScrim(WidgetTester tester) async {
    await tester.tapAt(const Offset(60, 400));
    await _settle(tester);
  }

  testWidgets('חלון צר: הקשה על ההצללה סוגרת את השכבה והנעיצה נשמרת', (
    tester,
  ) async {
    await pumpPinned(tester);
    await resize(tester, _narrow);
    expect(_paneOpen(tester), isTrue, reason: 'הצמצום עצמו אינו סוגר');

    await tapScrim(tester);

    expect(_paneOpen(tester), isFalse);
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);
    expect(_toggleIsOpen(tester), isFalse);
  });

  testWidgets('Esc סוגר את השכבה והנעיצה נשמרת', (tester) async {
    await pumpPinned(tester);
    await resize(tester, _narrow);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);

    expect(_paneOpen(tester), isFalse);
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);
  });

  testWidgets('כפתור הניווט סוגר ופותח את השכבה, והנעיצה נשמרת', (
    tester,
  ) async {
    await pumpPinned(tester);
    await resize(tester, _narrow);

    await tester.tap(find.byType(NavPanelToggleButton));
    await _settle(tester);
    expect(_paneOpen(tester), isFalse);
    expect(_toggleIsOpen(tester), isFalse);

    await tester.tap(find.byType(NavPanelToggleButton));
    await _settle(tester);
    expect(_paneOpen(tester), isTrue);
    expect(_toggleIsOpen(tester), isTrue);
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);
  });

  testWidgets('אחרי סגירת השכבה, הרחבת החלון פותחת את החלונית שוב', (
    tester,
  ) async {
    await pumpPinned(tester);
    await resize(tester, _narrow);
    await tapScrim(tester);
    expect(_paneOpen(tester), isFalse);

    await resize(tester, _wide);

    expect(_paneOpen(tester), isTrue);
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);
    // וחלון צר נוסף: השכבה נפתחת (לא נשארת סגורה מהפעם הקודמת).
    await resize(tester, _narrow);
    expect(_paneOpen(tester), isTrue);
  });

  testWidgets('ביטול נעיצה אחרי סגירת השכבה משאיר את החלונית סגורה', (
    tester,
  ) async {
    await pumpPinned(tester);
    await resize(tester, _narrow);
    await tapScrim(tester);

    await tester.tap(find.byTooltip('בטל נעיצה'));
    await _settle(tester);

    expect(_paneOpen(tester), isFalse);
    expect(find.byTooltip('נעץ את החלונית'), findsNothing);
  });

  testWidgets('חלון רחב: חלונית נעוצה נשארת פתוחה גם אחרי לחיצה על הכפתור', (
    tester,
  ) async {
    await pumpPinned(tester);

    await tester.tap(find.byType(NavPanelToggleButton));
    await _settle(tester);

    expect(_paneOpen(tester), isTrue);
    expect(_toggleIsOpen(tester), isTrue);
  });
}

bool _paneOpen(WidgetTester tester) =>
    tester.widget<NavSidePanel>(find.byType(NavSidePanel)).isOpen;

bool _toggleIsOpen(WidgetTester tester) => tester
    .widget<NavPanelToggleButton>(find.byType(NavPanelToggleButton))
    .isOpen;

// מסך המפרשים מציג אינדיקטור טעינה מסתובב, ולכן pumpAndSettle אינו מסתיים.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}
