import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

// חלונית ניווט נעוצה בכרטיסיית המפרשים של ספר טקסט, בחלון צר: היא שכבה עם
// הצללה. הקשה על ההצללה, Esc וכפתור הניווט סוגרים רק את השכבה; הנעיצה נשמרת,
// והחלונית נפתחת שוב מעצמה כשהחלון מתרחב (סעיף 11, החלטת הבעלים ג).

TextBookLoaded _loaded(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: const ['שורה א', 'שורה ב'],
  fontSize: 25,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: [TocEntry(text: 'פרק א', index: 0)],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

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
    final book = TextBook(title: 'חולין');
    final tabBloc = StubTextBookBloc(_loaded(book));
    final sourceTab = TextBookTab(book: book, index: 0);
    final tab = CommentatorsTab(sourceTab: sourceTab, blocOverride: tabBloc)
      ..selectedCommentators = const [];
    final settings = StubSettingsBloc();
    final notes = StubPersonalNotesBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.close();
      await notes.close();
      await tabBloc.close();
      sourceTab.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
          ],
          child: Scaffold(
            body: CommentatorsTabScreen(tab: tab, openBookCallback: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    if (!_paneOpen(tester)) {
      await tester.tap(find.byType(NavPanelToggleButton));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('נעץ את החלונית'));
    await tester.pumpAndSettle();
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  // ההצללה מכסה את הצד הרחוק מהחלונית (החלונית בימין).
  Future<void> tapScrim(WidgetTester tester) async {
    await tester.tapAt(const Offset(60, 400));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    expect(_paneOpen(tester), isFalse);
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);
  });

  testWidgets('כפתור הניווט סוגר ופותח את השכבה, והנעיצה נשמרת', (
    tester,
  ) async {
    await pumpPinned(tester);
    await resize(tester, _narrow);

    await tester.tap(find.byType(NavPanelToggleButton));
    await tester.pumpAndSettle();
    expect(_paneOpen(tester), isFalse);
    expect(_toggleIsOpen(tester), isFalse);

    await tester.tap(find.byType(NavPanelToggleButton));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    expect(_paneOpen(tester), isFalse);
    expect(find.byTooltip('נעץ את החלונית'), findsNothing);
  });

  testWidgets('חלון רחב: חלונית נעוצה נשארת פתוחה גם אחרי לחיצה על הכפתור', (
    tester,
  ) async {
    await pumpPinned(tester);

    await tester.tap(find.byType(NavPanelToggleButton));
    await tester.pumpAndSettle();

    expect(_paneOpen(tester), isTrue);
    expect(_toggleIsOpen(tester), isTrue);
  });
}

bool _paneOpen(WidgetTester tester) =>
    tester.widget<NavSidePanel>(find.byType(NavSidePanel)).isOpen;

bool _toggleIsOpen(WidgetTester tester) => tester
    .widget<NavPanelToggleButton>(find.byType(NavPanelToggleButton))
    .isOpen;
