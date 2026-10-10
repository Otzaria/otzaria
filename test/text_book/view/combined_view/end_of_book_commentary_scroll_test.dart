import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const _title = 'ספר בדיקה';

// כמו סוף מסכת: פסקאות ואחריהן שורת סיום גבוהה.
final _content = <String>[
  for (var i = 0; i < 20; i++) 'פסקה$i ${List.filled(30, 'מילה$i').join(' ')}',
  for (var i = 20; i < 23; i++) 'פסקה$i ${List.filled(6, 'מילה$i').join(' ')}',
  '<big><strong>${List.filled(3, 'הדרן עלך המגרש וסליקא לה מסכת גיטין').join('<br>')}</strong></big>',
];

final _lastIndex = _content.length - 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  /// פותח את התצוגה המשולבת (מפרשים מתחת לטקסט) ב-[jumpIndex] (ברירת מחדל:
  /// סוף הספר), לוחץ על [paragraph] ומחזיר את המיקומים לפני הלחיצה ואחריה.
  Future<({Map<int, ItemPosition> before, Map<int, ItemPosition> after})>
  tapParagraph(
    WidgetTester tester,
    int paragraph, {
    int? jumpIndex,
    double alignment = 0,
  }) async {
    tester.view.physicalSize = const Size(620, 880);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bloc = _TextBookBloc(
      TextBookLoaded(
        book: TextBook(title: _title),
        showLeftPane: false,
        content: _content,
        fontSize: 25,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const ['רש"י'],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        visibleLinks: const [],
        linksByLine: {
          for (var line = 1; line <= _content.length; line++)
            line: [
              Link(
                heRef: 'רש"י $line',
                index1: line,
                path2: 'רש"י',
                index2: line,
                connectionType: 'commentary',
              ),
            ],
        },
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: List.generate(_content.length, (i) => i),
        selectedIndex: null,
        pinLeftPane: false,
        searchText: '',
        scrollController: ItemScrollController(),
        positionsListener: ItemPositionsListener.create(),
      ),
    );
    final notesBloc = _PersonalNotesBloc(const PersonalNotesState.initial());
    final settingsBloc = _SettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: TextBook(title: _title), index: 0);
    addTearDown(bloc.close);
    addTearDown(notesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CombinedView(
              data: _content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 25,
              showCommentaryAsExpansionTiles: true,
              tab: tab,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // ברירת המחדל כמו Ctrl+End: הרשימה נעצרת בסוף הספר.
    tab.scrollController.jumpTo(
      index: jumpIndex ?? _lastIndex,
      alignment: alignment,
    );
    await tester.pumpAndSettle();

    Map<int, ItemPosition> positions() => {
      for (final p in tab.positionsListener.itemPositions.value) p.index: p,
    };
    final before = positions();
    if (jumpIndex == null) {
      expect(
        before[_lastIndex]!.itemTrailingEdge,
        moreOrLessEquals(1.0, epsilon: 1e-3),
      );
    }

    final target = find.byKey(ValueKey('html_${_title}_$paragraph'));
    await tester.tapAt(
      tester.getRect(target).bottomCenter - const Offset(0, 10),
      kind: PointerDeviceKind.mouse,
    );
    // פריימים לאורך הזמן: הגלילה האוטומטית מתוזמנת אחרי פריים, לא מיד.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect((bloc.state as TextBookLoaded).selectedIndex, paragraph);
    return (before: before, after: positions());
  }

  group('בחירת פסקה בסוף הספר לא מקפיצה את הרשימה אחורה (issue #1798)', () {
    // הפסקה הבאה כבר מעל קו ה-90%: אין גלילה אחורה, וסוף הספר נשאר בתחתית.
    testWidgets('הפסקה שלפני האחרונה', (tester) async {
      final paragraph = _lastIndex - 1;
      final result = await tapParagraph(tester, paragraph);
      expect(
        result.after[paragraph]!.itemLeadingEdge,
        lessThanOrEqualTo(result.before[paragraph]!.itemLeadingEdge + 1e-3),
      );
      expect(
        result.after[_lastIndex]!.itemTrailingEdge,
        moreOrLessEquals(1.0, epsilon: 1e-3),
      );
    });

    // אין טקסט הבא; סוף הספר נשאר בתחתית המסך והכרטיס נחשף מעליו.
    testWidgets('הפסקה האחרונה — סוף הספר נשאר בתחתית', (tester) async {
      final result = await tapParagraph(tester, _lastIndex);
      final last = result.after[_lastIndex]!;
      expect(last.itemTrailingEdge, moreOrLessEquals(1.0, epsilon: 1e-3));
      expect(last.itemLeadingEdge, greaterThanOrEqualTo(0));
    });

    // פסקה שתחילתה מעל המסך אינה ניתנת לעיגון; הגלילה עדיין חושפת את הכרטיס.
    testWidgets('פסקה שחלקה מעל המסך — הכרטיס נחשף', (tester) async {
      final result = await tapParagraph(
        tester,
        4,
        jumpIndex: 5,
        alignment: 0.2,
      );
      expect(result.before[4]!.itemLeadingEdge, lessThan(0));
      expect(
        result.after[5]!.itemLeadingEdge,
        moreOrLessEquals(0.9, epsilon: 1e-3),
      );
    });
  });
}

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<UpdateSelectedIndex>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(
          selectedIndex: event.index,
          clearSelectedIndex: event.index == null,
          selectedIndices: {?event.index},
          clearSelectedIndices: event.index == null,
        ),
      ),
    );
    on<TextBookEvent>((event, emit) {});
  }

  @override
  late final TextBookRepository repository = _TextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _PersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
