import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/reading_area_width.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

List<String> _content() =>
    List.generate(80, (i) => List.filled(40, 'מילה$i').join(' '));

TextBookLoaded _loadedState(List<String> content) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: content,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: null,
  pinLeftPane: false,
  searchText: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpReader(
    WidgetTester tester,
    Widget Function(List<String> content) reader, {
    double textMaxWidth = 0,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final content = _content();
    final textBookBloc = StubTextBookBloc(_loadedState(content));
    final personalNotesBloc = StubPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = StubSettingsBloc(
      SettingsState.initial().copyWith(textMaxWidth: textMaxWidth),
    );
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(body: reader(content)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<LineScrollController> pumpCombined(
    WidgetTester tester, {
    double textMaxWidth = 0,
    bool isPreviewMode = false,
    bool pinnedPane = false,
  }) async {
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(tab.dispose);
    await pumpReader(tester, textMaxWidth: textMaxWidth, (content) {
      final view = CombinedView(
        data: content,
        openBookCallback: (_) {},
        openLeftPaneTab: (_, {searchText}) {},
        textSize: 18,
        showCommentaryAsExpansionTiles: false,
        tab: tab,
        isPreviewMode: isPreviewMode,
      );
      return pinnedPane
          ? AdaptiveSidePane(
              isOpen: true,
              mainContent: view,
              paneContent: const SizedBox.expand(),
              onClose: () {},
            )
          : view;
    });
    return tab.lines;
  }

  /// לחיצה בשוליים שליד תחילת השורה אינה מגיעה למסילה, והמסילה עצמה עדיין
  /// מנווטת.
  Future<void> expectRailClearOfText(
    WidgetTester tester,
    LineScrollController lines,
  ) async {
    final track = tester.getRect(
      find.byKey(ScrollablePositionedListScrollbar.trackKey),
    );
    final text = tester.getRect(find.byType(SmartTextWidget).first);
    final position = lines.itemController.scrollController!.position;
    final y = track.bottom - 10;

    // בעברית תחילת השורה בימין, והמסילה מימינה.
    await tester.tapAt(Offset(text.right + kTextColumnMinMargin - 4, y));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      position.pixels,
      0,
      reason: 'לחיצה בשוליים שליד תחילת השורה נתפסה במסילה והקפיצה את הספר',
    );
    expect(track.left - text.right, greaterThanOrEqualTo(kTextColumnMinMargin));

    await tester.tapAt(Offset(track.center.dx, y));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(position.pixels, greaterThan(0), reason: 'המסילה מפסיקה לנווט');
  }

  group('מרווח בין הטקסט למסילה (issue #2450)', () {
    for (final (name, textMaxWidth, pinnedPane) in [
      ('רוחב מלא', 0.0, false),
      ('רוחב מלא עם חלונית נעוצה', 0.0, true),
      ('רוחב מוגבל', 500.0, false),
      ('רוחב מוגבל צר מהיעד, עם חלונית נעוצה', 2000.0, true),
    ]) {
      testWidgets('קורא רגיל — $name', (tester) async {
        final lines = await pumpCombined(
          tester,
          textMaxWidth: textMaxWidth,
          pinnedPane: pinnedPane,
        );
        await expectRailClearOfText(tester, lines);
      });
    }

    testWidgets('תצוגה מקדימה', (tester) async {
      final lines = await pumpCombined(tester, isPreviewMode: true);
      await expectRailClearOfText(tester, lines);
    });

    testWidgets('צורת הדף', (tester) async {
      final lines = LineScrollController();
      addTearDown(lines.dispose);
      await pumpReader(
        tester,
        (content) => SimpleTextViewer(
          content: content,
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
          lines: lines,
        ),
      );
      await expectRailClearOfText(tester, lines);
    });
  });
}
