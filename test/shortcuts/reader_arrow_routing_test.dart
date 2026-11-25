import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:provider/provider.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../test_helpers/reading_toc.dart';
import '../test_helpers/stub_personal_notes_bloc.dart';
import '../test_helpers/stub_settings_bloc.dart';
import '../test_helpers/stub_tabs_bloc.dart';
import '../test_helpers/stub_text_book_bloc.dart';

/// מקש חץ שבוטל באזור הקריאה ושויך לפעולה אחרת מגיע אליה בכל תצוגה, ולא
/// מעביר פוקוס (issue #2851).
final List<String> _lines = [
  for (var chapter = 1; chapter <= 3; chapter++) ...[
    '<h2>פרק $chapter</h2>',
    for (var verse = 1; verse <= 3; verse++) 'פסוק $verse בפרק $chapter',
  ],
];

TextBookLoaded _state() => TextBookLoaded(
  book: TextBook(title: 'ספר חיצים'),
  showLeftPane: false,
  content: _lines,
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  linksByLine: const {},
  tableOfContents: headerToc(_lines),
  visibleIndices: const [0],
  selectedIndex: 0,
  searchText: '',
);

class _RecordingNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _RecordingNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.reading)) {
    on<NavigationEvent>((event, _) => events.add(event));
  }

  final List<NavigationEvent> events = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

enum _View { text, narrowText, pageShape, outside }

class _Harness {
  _Harness(this.tab, this.navigation, this.field);

  final TextBookTab tab;
  final _RecordingNavigationBloc navigation;
  final TextEditingController field;

  /// [קטע קודם, קטע הבא, דף/פרק קודם, דף/פרק הבא]
  List<int> get counts => [
    tab.navPreviousSegmentNotifier.value,
    tab.navNextSegmentNotifier.value,
    tab.navPreviousTocNotifier.value,
    tab.navNextTocNotifier.value,
  ];
}

Future<_Harness> _mount(
  WidgetTester tester,
  _View view,
  Map<String, String> shortcuts,
) async {
  for (final MapEntry(:key, :value) in shortcuts.entries) {
    await Settings.setValue<String>(key, value);
  }
  if (view == _View.narrowText) {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final initial = _state();
  final bloc = StubTextBookBloc(initial);
  final tab = TextBookTab(book: initial.book, index: 0, blocOverride: bloc);
  final tabs = StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
  final navigation = _RecordingNavigationBloc();
  final notes = StubPersonalNotesBloc();
  final settings = StubSettingsBloc(
    SettingsState.initial().copyWith(
      shortcuts: {...ShortcutValidator.defaultShortcuts, ...shortcuts},
    ),
  );
  final field = TextEditingController(text: 'אבג');
  final button = FocusNode(debugLabel: 'outside');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
    await tabs.close();
    await navigation.close();
    await notes.close();
    await settings.close();
    tab.dispose();
    field.dispose();
    button.dispose();
  });
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<SettingsBloc>.value(value: settings),
        BlocProvider<TabsBloc>.value(value: tabs),
        BlocProvider<NavigationBloc>.value(value: navigation),
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<PersonalNotesBloc>.value(value: notes),
        Provider<FocusRepository>.value(value: FocusRepository()),
      ],
      child: MaterialApp(
        builder: (_, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          body: KeyboardShortcuts(
            onFindRefRequested: () {},
            child: Column(
              children: [
                OutlinedButton(
                  focusNode: button,
                  onPressed: () {},
                  child: const Text('כפתור'),
                ),
                TextField(controller: field),
                if (view != _View.outside)
                  Expanded(
                    child: view == _View.pageShape
                        ? SimpleTextViewer(
                            content: _lines,
                            fontSize: 18,
                            openBookCallback: (_) {},
                            isMainText: true,
                            tab: tab,
                          )
                        : CombinedView(
                            data: _lines,
                            openBookCallback: (_) {},
                            openLeftPaneTab: (_, {searchText}) {},
                            textSize: 18,
                            showCommentaryAsExpansionTiles: true,
                            tab: tab,
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final readerFocus = switch (view) {
    _View.outside => button,
    _View.pageShape =>
      tester
          .widget<Focus>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Focus &&
                  widget.focusNode?.debugLabel == 'PageShapeContentFocus',
            ),
          )
          .focusNode!,
    _ =>
      tester
          .widget<ProgressiveScroll>(find.byType(ProgressiveScroll))
          .focusNode!,
  };
  readerFocus.requestFocus();
  await tester.pumpAndSettle();
  expect(FocusManager.instance.primaryFocus, same(readerFocus));
  return _Harness(tab, navigation, field);
}

/// לחיצה עם החזקה: KeyDown, שתי חזרות ו-KeyUp.
Future<void> _hold(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? modifier,
}) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyRepeatEvent(key);
  await tester.sendKeyRepeatEvent(key);
  await tester.sendKeyUpEvent(key);
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void _test(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      ShortcutHelper.isMacForTesting =
          defaultTargetPlatform == TargetPlatform.macOS;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      await body(tester);
    }, variant: TargetPlatformVariant.desktop());

LogicalKeyboardKey get _shortcutModifier =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    FocusRepository().resetForTesting();
  });

  for (final view in _View.values) {
    _test('← שבוטל באזור הקריאה ושויך ל"הדף/פרק הבא" מפעיל אותו '
        '(${view.name})', (tester) async {
      final harness = await _mount(tester, view, const {
        'key-shortcut-next-segment-reader': '',
        'key-shortcut-next-toc': 'arrowleft',
      });
      final focused = FocusManager.instance.primaryFocus;

      await _hold(tester, LogicalKeyboardKey.arrowLeft);

      expect(harness.counts, [0, 0, 0, 1]);
      expect(FocusManager.instance.primaryFocus, same(focused));
    });

    _test('Ctrl+← שבוטל באזור הקריאה ושויך ל"הקטע הבא" מפעיל אותו '
        '(${view.name})', (tester) async {
      final harness = await _mount(tester, view, const {
        'key-shortcut-next-toc-reader': '',
        'key-shortcut-next-segment': 'ctrl+arrowleft',
      });

      await _hold(
        tester,
        LogicalKeyboardKey.arrowLeft,
        modifier: _shortcutModifier,
      );

      expect(harness.counts, [0, 1, 0, 0]);
    });
  }

  for (final view in [_View.text, _View.outside]) {
    _test('← ששמור ל"הקטע הבא" פועל פעם אחת, ו-Alt+↓ פותח את הספרייה '
        '(${view.name})', (tester) async {
      final harness = await _mount(tester, view, const {
        'key-shortcut-next-segment': 'arrowleft',
        'key-shortcut-open-library-browser': 'alt+arrowdown',
      });

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(harness.counts, [0, 1, 0, 0]);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(harness.navigation.events, [
        const NavigateToScreen(Screen.library),
      ]);
      expect(harness.counts, [0, 1, 0, 0]);
    });
  }

  _test('חצים עם בחירה פעילה נשארים לבחירה', (tester) async {
    final harness = await _mount(tester, _View.text, const {
      'key-shortcut-next-toc-reader': '',
      'key-shortcut-next-segment': 'ctrl+arrowleft',
    });
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion).first,
    );
    region.selectAll();
    await tester.pump();
    final initial = region.selectionEndpoints.map((p) => p.point).toList();

    await _hold(
      tester,
      LogicalKeyboardKey.arrowRight,
      modifier: LogicalKeyboardKey.shiftLeft,
    );
    final afterShift = region.selectionEndpoints.map((p) => p.point).toList();
    expect(afterShift, isNot(initial));

    await _hold(
      tester,
      LogicalKeyboardKey.arrowLeft,
      modifier: _shortcutModifier,
    );
    expect(harness.counts, [0, 0, 0, 0]);
  });

  _test('← ששויך לפעולה נשאר להזזת הסמן בשדה טקסט', (tester) async {
    final harness = await _mount(tester, _View.text, const {
      'key-shortcut-next-segment-reader': '',
      'key-shortcut-next-toc': 'arrowleft',
    });
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    harness.field.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(
      harness.field.selection,
      isNot(const TextSelection.collapsed(offset: 1)),
    );
    expect(harness.counts, [0, 0, 0, 0]);
  });
}
