import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_bar_button.dart';

import '../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// שורת "ציוני המפרשים" בפאנל הסרגל חלה גם על המפרשים (#2372).
void main() {
  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  testWidgets('ציוני המפרשים בפאנל: שינוי למפרשים לא נוגע בגוף', (
    tester,
  ) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 0, true, const []),
    );
    final settings = _FakeSettingsBloc();
    addTearDown(bloc.close);
    addTearDown(settings.close);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    bloc.emit(
      TextBookLoaded(
        book: book,
        content: const ['שורה א'],
        fontSize: 20,
        showLeftPane: true,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        pinLeftPane: false,
        searchText: '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<TextBookBloc>.value(value: bloc),
                BlocProvider<SettingsBloc>.value(value: settings),
              ],
              child: const TextBookDisplayPanel(
                targets: [TextTarget.body, TextTarget.commentary],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // טבלה: שם השורה פעם אחת, ותא לכל מקטע (q12 Q7).
    expect(find.text('ציוני המפרשים'), findsOneWidget);

    // "הסתר" האחרון בפאנל שייך לשורת הציונים של מקטע המפרשים.
    final hide = find.text('הסתר').last;
    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pumpAndSettle();

    final state = bloc.state as TextBookLoaded;
    expect(
      state.displayOverrides.patchFor(TextDisplaySlot.commentaryDisplay),
      const TextDisplayPatch(anchorMarkers: MarkVisibility.hide),
    );
    expect(state.commentaryDisplayProfile.showAnchorMarkers, isFalse);
    expect(state.bodyDisplayProfile.showAnchorMarkers, isTrue);
    expect(
      state
          .displayProfile(
            target: TextTarget.commentary,
            channel: TextChannel.copy,
          )
          .showAnchorMarkers,
      isFalse,
    );
  });
}
