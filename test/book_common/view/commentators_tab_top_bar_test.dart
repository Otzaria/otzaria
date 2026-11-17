import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/commentators_tab_top_bar.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import '../../helpers/memory_settings_cache.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) => received.add(event));
  }

  final List<SettingsEvent> received = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BookmarksBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _BookmarksBloc() : super(BookmarkState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));
  testWidgets('shows the title and runs the screen actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _SettingsBloc();
    final allExpanded = ValueNotifier(true);
    addTearDown(() async {
      allExpanded.dispose();
      await settings.close();
    });
    final calls = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: Scaffold(
            body: CommentatorsTabTopBar(
              title: 'מפרשים על בראשית',
              prevMajorTooltip: 'הפרק הקודם',
              nextMajorTooltip: 'הפרק הבא',
              navPaneOpen: false,
              navPanePinned: false,
              onToggleNavPane: () => calls.add('pane'),
              onTogglePin: () => calls.add('pin'),
              onPrevMajor: () => calls.add('prevMajor'),
              onPrevMinor: () => calls.add('prevMinor'),
              onNextMinor: () => calls.add('nextMinor'),
              onNextMajor: () => calls.add('nextMajor'),
              textDisplayAction: ActionButtonData(
                widget: BarButton.icon(
                  tooltip: 'תצוגה',
                  icon: Icons.text_fields,
                  onPressed: () => calls.add('display'),
                ),
                icon: Icons.text_fields,
                tooltip: 'תצוגה',
                actionId: ToolbarActionId.textDisplay,
                onPressed: () => calls.add('display'),
              ),
              onPrint: () => calls.add('print'),
              onSearch: () => calls.add('search'),
              allExpanded: allExpanded,
              onToggleAllExpanded: () => calls.add('expand'),
              onAddBookmark: () => calls.add('bookmark'),
              book: TextBook(title: 'בראשית'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('מפרשים על בראשית'), findsOneWidget);
    expect(find.byTooltip('הפרק הקודם'), findsOneWidget);
    expect(find.byTooltip('כווץ את כל המפרשים'), findsOneWidget);

    for (final tooltip in [
      'הדפסה',
      'חיפוש',
      'הוסף סימניה',
      'הפרק הבא',
    ]) {
      await tester.tap(find.byTooltip(tooltip));
    }
    expect(calls, [
      'print',
      'search',
      'bookmark',
      'nextMajor',
    ]);

    await tester.tap(find.byTooltip('הגדל את גודל הטקסט'));
    await tester.tap(find.byTooltip('הקטן את גודל הטקסט'));
    await tester.pump();
    expect(
      settings.received.whereType<AdjustCommentatorsFontSize>().map(
        (e) => e.delta,
      ),
      [2, -2],
    );

    allExpanded.value = false;
    await tester.pump();
    expect(find.byTooltip('הרחב את כל המפרשים'), findsOneWidget);

    final bar = tester.widget<CommentatorsTabTopBar>(
      find.byType(CommentatorsTabTopBar),
    );
    final bookmarks = _BookmarksBloc();
    addTearDown(bookmarks.close);
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<BookmarkBloc>.value(value: bookmarks),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(alignment: Alignment.topCenter, child: bar),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('עוד פעולות'));
    await tester.pumpAndSettle();
    expect(find.text('סימניות בספר זה'), findsOneWidget);
    await tester.tap(find.text('סימניות בספר זה'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookmarksDialog>(find.byType(BookmarksDialog)).bookFilter,
      same(bar.book),
    );
    expect(
      tester.widget<BookmarkView>(find.byType(BookmarkView)).bookFilter,
      same(bar.book),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // q-comm-nav (סקירה שלישית של 4.11): כמו בקורא — החיצים בסרגל כל עוד
  // ארבעתם נכנסים במרכז, וקודמים לכותרת; אחרת כולם בראש "עוד".
  group('חיצי הניווט לפי הרוחב שנמדד', () {
    const arrows = ['הפרק הקודם', 'הקטע הקודם', 'הקטע הבא', 'הפרק הבא'];

    Future<List<String>> pumpAt(WidgetTester tester, double width) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = _SettingsBloc();
      final allExpanded = ValueNotifier(true);
      addTearDown(() async {
        allExpanded.dispose();
        await settings.close();
      });
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settings,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: CommentatorsTabTopBar(
                    title: 'מפרשים על בראשית',
                    prevMajorTooltip: 'הפרק הקודם',
                    nextMajorTooltip: 'הפרק הבא',
                    navPaneOpen: false,
                    navPanePinned: false,
                    onToggleNavPane: () {},
                    onTogglePin: () {},
                    onPrevMajor: () => calls.add('prevMajor'),
                    onPrevMinor: () => calls.add('prevMinor'),
                    onNextMinor: () => calls.add('nextMinor'),
                    onNextMajor: () => calls.add('nextMajor'),
                    textDisplayAction: ActionButtonData(
                      widget: BarButton.icon(
                        tooltip: 'תצוגה',
                        icon: Icons.text_fields,
                        onPressed: () {},
                      ),
                      icon: Icons.text_fields,
                      tooltip: 'תצוגה',
                      actionId: ToolbarActionId.textDisplay,
                      onPressed: () {},
                    ),
                    onPrint: () {},
                    onSearch: () {},
                    allExpanded: allExpanded,
                    onToggleAllExpanded: () {},
                    onAddBookmark: () {},
                    book: TextBook(title: 'בראשית'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return calls;
    }

    int arrowsShown() =>
        arrows.where((t) => find.byTooltip(t).evaluate().isNotEmpty).length;

    testWidgets('צר: אין מקום לארבעה — אף חץ בסרגל, וכולם בראש "עוד"', (
      tester,
    ) async {
      final calls = await pumpAt(tester, 360);
      expect(arrowsShown(), 0);
      expect(
        tester.getSize(find.byType(ReaderNavCenter)).width,
        lessThan(ReaderNavCenter.navButtonsWidth(compact: true)),
      );
      await tester.tap(find.byTooltip('עוד פעולות'));
      await tester.pumpAndSettle();
      expect(arrowsShown(), 4);
      // שורת הראש לא סוגרת את התפריט: אפשר לדפדף כמה פעמים ברצף.
      await tester.tap(find.byTooltip('הקטע הבא'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('הפרק הבא'));
      await tester.pumpAndSettle();
      expect(calls, ['nextMinor', 'nextMajor']);
    });

    testWidgets('רחב: ארבעתם בסרגל, ולא בתפריט', (tester) async {
      await pumpAt(tester, 1200);
      expect(arrowsShown(), 4);
      await tester.tap(find.byTooltip('עוד פעולות'));
      await tester.pumpAndSettle();
      for (final tooltip in arrows) {
        expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      }
    });

    testWidgets('בכל רוחב: ארבעה או אפס, לפי מה שהמרכז קיבל (#891)', (
      tester,
    ) async {
      for (var width = 280.0; width <= 900; width += 20) {
        await pumpAt(tester, width);
        final shown = arrowsShown();
        final center = tester.getSize(find.byType(ReaderNavCenter)).width;
        expect(shown, anyOf(0, 4), reason: '$width');
        expect(
          shown == 4,
          ReaderNavCenter.navFits(center, isCompact: false),
          reason: 'bar=$width center=$center',
        );
      }
    });
  });
}
