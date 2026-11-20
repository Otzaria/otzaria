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
  _FakeSettingsBloc([TextDisplayPolicy? policy])
    : super(
        policy == null
            ? SettingsState.initial()
            : SettingsState.initial().copyWith(textDisplayPolicy: policy),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// המתג בשורה שהכותרת שלה [title]; [last] — המופע האחרון (מקטע המפרשים).
Finder _switchOf(String title, {bool last = false}) {
  final text = last ? find.text(title).last : find.text(title).first;
  final row = find.ancestor(of: text, matching: find.byType(Row)).first;
  return find.descendant(of: row, matching: find.byType(Switch));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// חלונית הסרגל מעל TextBookBloc אמיתי.
void main() {
  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  Future<TextBookBloc> pumpPanel(
    WidgetTester tester, {
    TextDisplayPolicy? settingsPolicy,
  }) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 0, true, const []),
    );
    final settings = _FakeSettingsBloc(settingsPolicy);
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
    return bloc;
  }

  /// שורת "ציוני המפרשים" בפאנל הסרגל חלה גם על המפרשים (#2372).
  testWidgets('ציוני המפרשים בפאנל: שינוי למפרשים לא נוגע בגוף', (
    tester,
  ) async {
    final bloc = await pumpPanel(tester);

    // מקטע המפרשים מקופל: רק שורת הציונים של גוף הספר גלויה.
    expect(find.text('ציוני המפרשים'), findsOneWidget);
    await _tap(tester, find.text('מפרשים'));
    expect(find.text('ציוני המפרשים'), findsNWidgets(2));

    // שורת הציונים האחרונה שייכת למקטע המפרשים.
    await _tap(tester, _switchOf('ציוני המפרשים', last: true));

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

  testWidgets('שינוי שבוטל נמחק מהעקיפה, ו"איפוס" נעלם', (tester) async {
    final bloc = await pumpPanel(tester);
    expect(find.text('איפוס'), findsNothing);

    await _tap(tester, _switchOf('סימני פיסוק'));
    expect(
      (bloc.state as TextBookLoaded).bodyDisplayProfile.removePunctuation,
      isTrue,
    );
    expect(find.text('איפוס'), findsOneWidget);

    await _tap(tester, _switchOf('סימני פיסוק'));
    final state = bloc.state as TextBookLoaded;
    expect(state.bodyDisplayProfile.removePunctuation, isFalse);
    expect(state.displayOverrides.isEmpty, isTrue);
    expect(find.text('איפוס'), findsNothing);
  });

  testWidgets('"איפוס" מנקה את כל העקיפות', (tester) async {
    final bloc = await pumpPanel(tester);

    await _tap(tester, _switchOf('ניקוד'));
    await _tap(tester, find.text('איפוס'));

    final state = bloc.state as TextBookLoaded;
    expect(state.displayOverrides.isEmpty, isTrue);
    expect(state.bodyDisplayProfile.removeNikud, isFalse);
    expect(find.text('איפוס'), findsNothing);
  });

  testWidgets(
    '"שמות הקודש" המשותף: הצג — ככתבם בשני המקטעים; הסתר — הנוסח מההגדרות ובכינוי',
    (tester) async {
      // בהגדרות נבחר הנוסח ה' לשם הוי"ה.
      final bloc = await pumpPanel(
        tester,
        settingsPolicy: TextDisplayPolicy(
          general: TextDisplayLayer({
            TextDisplaySlot.root: const TextDisplayPatch(
              holyName: HolyNameDisplay.hehApostrophe,
            ),
          }),
          tanach: TextDisplayLayer.empty,
        ),
      );
      expect(find.text('בגוף הספר ובמפרשים'), findsOneWidget);
      expect(find.text('שמות הקודש'), findsOneWidget);

      await _tap(tester, _switchOf('שמות הקודש'));
      var state = bloc.state as TextBookLoaded;
      for (final target in TextTarget.values) {
        final profile = state.displayProfile(target: target);
        expect(profile.holyName, HolyNameDisplay.asIs, reason: target.name);
        expect(
          profile.divineNames,
          DivineNamesDisplay.asIs,
          reason: target.name,
        );
      }
      expect(tester.widget<Switch>(_switchOf('שמות הקודש')).value, isTrue);

      await _tap(tester, _switchOf('שמות הקודש'));
      state = bloc.state as TextBookLoaded;
      for (final target in TextTarget.values) {
        final profile = state.displayProfile(target: target);
        expect(
          profile.holyName,
          HolyNameDisplay.hehApostrophe,
          reason: target.name,
        );
        expect(
          profile.divineNames,
          DivineNamesDisplay.substitute,
          reason: target.name,
        );
      }
      expect(tester.widget<Switch>(_switchOf('שמות הקודש')).value, isFalse);
    },
  );
}
