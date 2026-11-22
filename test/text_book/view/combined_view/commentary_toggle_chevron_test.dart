import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _title = 'ספר בדיקה';

final _content = <String>[
  for (var i = 0; i < 5; i++) 'פסקה$i ${List.filled(12, 'מילה$i').join(' ')}',
];

/// לפסקאות 0–2 יש מפרש; ל-3 ו-4 אין.
const _withCommentary = 3;

const _continuousContent = ['שורה ראשונה', 'שורה שניה', 'שורה שלישית'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<_TextBookBloc> pumpReader(
    WidgetTester tester, {
    bool opensOnTextTap = true,
    bool continuous = false,
  }) async {
    tester.view.physicalSize = const Size(620, 880);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // רציף: פסקה ממוזגת אחת, ולשורה הראשונה והשלישית יש מפרשים.
    final content = continuous ? _continuousContent : _content;
    final links = [
      if (continuous) ...[_FixtureLink(1), _FixtureLink(3)],
      if (!continuous)
        for (var line = 1; line <= _withCommentary; line++) _FixtureLink(line),
    ];
    final bloc = _TextBookBloc(
      TextBookLoaded(
        book: TextBook(title: _title),
        showLeftPane: false,
        content: content,
        fontSize: 25,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const ['רש"י'],
        commentatorGroups: const [
          CommentatorGroup(title: 'ראשונים', commentators: ['רש"י']),
        ],
        availableCommentators: const ['רש"י'],
        links: links,
        visibleLinks: const [],
        linksByLine: {
          for (final link in links) link.index1: [link],
        },
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        selectedIndex: null,
        pinLeftPane: false,
        searchText: '',
        continuousReadingMode: continuous,
      ),
    );
    final notesBloc = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settingsBloc = StubSettingsBloc(
      SettingsState.initial().copyWith(
        commentaryOpensOnTextTap: opensOnTextTap,
      ),
    );
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
              data: content,
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
    await tester.pumpAndSettle();
    return bloc;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 301));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Rect paragraphRect(WidgetTester tester, int line) =>
      tester.getRect(find.byKey(ValueKey('html_${_title}_$line')));

  int? selected(_TextBookBloc bloc) =>
      (bloc.state as TextBookLoaded).selectedIndex;

  group('commentaries-below toggle control (issue #2835)', () {
    testWidgets('חץ ליד פסקה עם מפרשים פותח וסוגר אותם', (tester) async {
      final bloc = await pumpReader(tester);

      // חץ רק לפסקאות שיש להן מפרשים.
      expect(find.byTooltip('הצג מפרשים'), findsNWidgets(_withCommentary));

      // החץ בקצה הפסקה, מחוץ לטקסט עצמו.
      final chevron = find.byTooltip('הצג מפרשים').at(1);
      final text = paragraphRect(tester, 1);
      final chevronRect = tester.getRect(chevron);
      expect(chevronRect.right, lessThanOrEqualTo(text.left + 0.5));
      expect(chevronRect.top, closeTo(text.top, 30));

      await tester.tap(chevron);
      await settle(tester);
      expect(selected(bloc), 1);
      expect(find.byKey(const ValueKey('commentary_card_1')), findsOneWidget);

      await tester.tap(find.byTooltip('הסתר מפרשים'));
      await settle(tester);
      expect(selected(bloc), isNull);
      expect(find.byKey(const ValueKey('commentary_card_1')), findsNothing);
    });

    testWidgets('ברירת המחדל: לחיצה על הטקסט פותחת כמו קודם', (tester) async {
      final bloc = await pumpReader(tester);

      await tester.tapAt(
        paragraphRect(tester, 2).center,
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);

      expect(selected(bloc), 2);
      expect(find.byKey(const ValueKey('commentary_card_2')), findsOneWidget);
    });

    testWidgets('כשהאפשרות כבויה, לחיצה על הטקסט לא פותחת', (tester) async {
      final bloc = await pumpReader(tester, opensOnTextTap: false);

      await tester.tapAt(
        paragraphRect(tester, 2).center,
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);

      expect(selected(bloc), isNull);
      expect(find.byKey(const ValueKey('commentary_card_2')), findsNothing);

      // החץ עדיין פותח.
      await tester.tap(find.byTooltip('הצג מפרשים').at(2));
      await settle(tester);
      expect(selected(bloc), 2);
    });

    testWidgets(
      'כשהאפשרות כבויה, בפסקה רציפה החץ פותח את מפרשי השורה שהקורא לחץ עליה',
      (tester) async {
        final bloc = await pumpReader(
          tester,
          opensOnTextTap: false,
          continuous: true,
        );
        expect(find.byTooltip('הצג מפרשים'), findsOneWidget);

        final third = find.textContaining('שורה שלישית', findRichText: true);
        final paragraph = tester.renderObject<RenderParagraph>(third.last);
        final text = paragraph.text.toPlainText();
        final start = text.indexOf('שורה שלישית');
        final box = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: start,
                extentOffset: start + 'שורה שלישית'.length,
              ),
            )
            .first;
        await tester.tapAt(
          paragraph.localToGlobal(box.toRect().center),
          kind: PointerDeviceKind.mouse,
        );
        await settle(tester);
        expect(selected(bloc), isNull);

        await tester.tap(find.byTooltip('הצג מפרשים'));
        await settle(tester);
        expect(selected(bloc), 2);
      },
    );

    testWidgets('גרירה לבחירת טקסט לא פותחת את המפרשים', (tester) async {
      final bloc = await pumpReader(tester);
      final rect = paragraphRect(tester, 2);

      final gesture = await tester.startGesture(
        rect.centerRight - const Offset(10, 0),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-80, 0));
      await gesture.up();
      await settle(tester);

      expect(selected(bloc), isNull);
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

class _FixtureLink extends Link {
  _FixtureLink(int line)
    : _content = Future.value('מפרש לדוגמה ${'מילה ' * 20}'),
      super(
        heRef: 'רש"י $line',
        index1: line,
        path2: 'רש"י',
        index2: line,
        connectionType: 'commentary',
      ) {
    _content.then((text) => _loaded = text);
  }

  final Future<String> _content;
  String? _loaded;
  @override
  Future<String> get content => _content;
  @override
  String? get loadedContent => _loaded;
  @override
  Future<String> get displayReference => Future.value(heRef);
}
