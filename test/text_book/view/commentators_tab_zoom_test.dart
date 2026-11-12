import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';
import '../../unit/mocks/mock_settings_repository.mocks.dart';

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
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('לחיצות זום רצופות מעדכנות את הגופן המוצג גם בשמירה איטית', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final book = TextBook(title: 'חולין');
    final sourceBloc = StubTextBookBloc(_loaded(book));
    final tabBloc = StubTextBookBloc(_loaded(book));
    final sourceTab = TextBookTab(
      book: book,
      index: 0,
      blocOverride: sourceBloc,
    );
    final tab = CommentatorsTab(sourceTab: sourceTab, blocOverride: tabBloc);
    final repository = MockSettingsRepository();
    final firstWrite = Completer<void>();
    final writes = <double>[];
    when(repository.updateCommentatorsFontSize(any)).thenAnswer((invocation) {
      writes.add(invocation.positionalArguments.single as double);
      return writes.length == 1 ? firstWrite.future : Future<void>.value();
    });
    final settings = SettingsBloc(repository: repository);
    final notes = StubPersonalNotesBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.close();
      await notes.close();
      await tabBloc.close();
      await sourceBloc.close();
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
    expect(
      tester
          .widget<CommentaryListBase>(find.byType(CommentaryListBase))
          .fontSize,
      22,
    );

    await tester.tap(find.byTooltip('הגדל את גודל הטקסט').first);
    await tester.pump();
    await tester.tap(find.byTooltip('הגדל את גודל הטקסט').first);
    await tester.pump();
    expect(writes, [24.0]);
    expect(
      tester
          .widget<CommentaryListBase>(find.byType(CommentaryListBase))
          .fontSize,
      22,
    );

    firstWrite.complete();
    await tester.pump();
    await tester.pump();
    expect(writes, [24.0, 26.0]);
    expect(
      tester
          .widget<CommentaryListBase>(find.byType(CommentaryListBase))
          .fontSize,
      26,
    );

    await tester.tap(find.byTooltip('הקטן את גודל הטקסט').first);
    await tester.pump();
    await tester.pump();
    expect(writes, [24.0, 26.0, 24.0]);
    expect(
      tester
          .widget<CommentaryListBase>(find.byType(CommentaryListBase))
          .fontSize,
      24,
    );
  });

  testWidgets('קיצור חלונית הניווט פותח וסוגר אותה בכרטיסיית המפרשים '
      '(issue #2678)', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final book = TextBook(title: 'חולין');
    final tabBloc = StubTextBookBloc(_loaded(book));
    final sourceTab = TextBookTab(book: book, index: 0);
    final tab = CommentatorsTab(sourceTab: sourceTab, blocOverride: tabBloc);
    final settings = SettingsBloc(repository: MockSettingsRepository());
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
    bool paneOpen() =>
        tester.widget<NavSidePanel>(find.byType(NavSidePanel)).isOpen;
    // בלי מפרשים הרשימה פותחת את לשונית הבחירה, ולכן נבדק היפוך המצב.
    final initial = paneOpen();
    final modifier = ShortcutHelper.usesMacModifiers
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    for (final expected in [!initial, initial]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(paneOpen(), expected);
    }
  });
}
