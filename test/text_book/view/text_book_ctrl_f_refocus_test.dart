import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_tabs_bloc.dart';

/// Ctrl+F כשחלונית החיפוש כבר פתוחה והפוקוס עבר לטקסט: השדה ממוקד ונבחר
/// מיד, ולא רק אחרי שהעכבר עובר מעל החלונית (issue #5037).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusRepository focusRepository;
  late _TestBookmarkBloc bookmarkBloc;
  late PersonalNotesBloc personalNotesBloc;
  late TourCubit tourCubit;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    focusRepository = FocusRepository()..resetForTesting();
    bookmarkBloc = _TestBookmarkBloc();
    personalNotesBloc = PersonalNotesBloc();
    tourCubit = TourCubit();
  });

  tearDown(() async {
    await bookmarkBloc.close();
    await personalNotesBloc.close();
    await tourCubit.close();
    focusRepository.resetForTesting();
    ShortcutHelper.isMacForTesting = null;
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = TextBookBloc(
      repository: TextBookRepository(fileSystem: FileSystemData.instance),
      initialState: TextBookInitial.named(book, 0, true, const []),
    );
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    bloc.emit(
      TextBookLoaded(
        book: book,
        content: const ['שורה א', 'שורה ב'],
        fontSize: 18,
        showLeftPane: true,
        showSplitView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        pinLeftPane: true,
        searchText: '',
      ),
    );
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final settingsBloc = StubSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await tabsBloc.close();
      await settingsBloc.close();
      tab.dispose();
    });

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: focusRepository),
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: _FakeShamorZachorDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: _FakeShamorZachorProgressProvider(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
          ],
          child: MaterialApp(
            home: TextBookViewerBloc(
              tab: tab,
              isInCombinedView: false,
              openBookCallback: (_) {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  for (final mac in [false, true]) {
    final modifier = mac
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;

    testWidgets(
      '${mac ? 'Cmd' : 'Ctrl'}+F חוזר ממקד ובוחר את שדה החיפוש בלי ריחוף '
      'עכבר (issue #5037)',
      (tester) async {
        ShortcutHelper.isMacForTesting = mac;
        await pumpScreen(tester);

        Future<void> pressFind() async {
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          await tester.sendKeyUpEvent(modifier);
        }

        await pressFind();
        await settle(tester);
        final field = tester.widget<EditableText>(
          find.descendant(
            of: find.byType(TextBookSearchView),
            matching: find.byType(EditableText),
          ),
        );
        expect(FocusManager.instance.primaryFocus, field.focusNode);
        // החיפוש הקודם נשאר בשדה, והסמן בסופו כמו אחרי הקלדה.
        field.controller.value = const TextEditingValue(
          text: 'מילה',
          selection: TextSelection.collapsed(offset: 4),
        );

        // לחיצת עכבר בטקסט, כמו על תוצאה, מעבירה את הפוקוס לאזור הקריאה.
        await tester.tapAt(
          tester.getCenter(find.byType(CombinedView)),
          kind: PointerDeviceKind.mouse,
        );
        await settle(tester);
        expect(field.focusNode.hasFocus, isFalse);

        await pressFind();
        await tester.pump();
        await tester.pump();

        expect(FocusManager.instance.primaryFocus, field.focusNode);
        expect(
          field.controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
          reason: 'החיפוש הקודם נבחר, כך שהקלדה מחליפה אותו',
        );
      },
      variant: TargetPlatformVariant.only(
        mac ? TargetPlatform.macOS : TargetPlatform.windows,
      ),
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  @override
  Future<void> ensureLoaded() async {}
}
