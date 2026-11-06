import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/bloc/commentary_search_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';

import '../../support/search_engine_test_init.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  CommentarySearchBloc build() =>
      CommentarySearchBloc(keyOf: (link) => link.path2);
  CommentarySearchRequested request(
    List<Link> links,
    String query, {
    TextDisplayProfile profile = TextDisplayProfile.defaults,
  }) => CommentarySearchRequested(
    links: links,
    query: query,
    displayProfile: profile,
    includeSnippets: true,
  );

  group('בעלות משותפת על חיפוש מפרשים', () {
    blocTest<CommentarySearchBloc, CommentarySearchState>(
      'טוען גם פריטים שלא נבנו ומפרסם ספירות וקטעים עם אותם היסטים',
      build: build,
      act: (bloc) async {
        final completed = bloc.stream.firstWhere(
          (state) =>
              state.counts.containsKey('ראשון') &&
              state.counts.containsKey('שני'),
        );
        bloc.add(
          request([
            _Link('ראשון', Future.value('<b>וַיֹּאמֶר</b> משה אמר משה')),
            _Link('שני', Future.value('אמר רבי אמר')),
          ], 'אמר'),
        );
        await completed;
      },
      verify: (bloc) {
        expect(bloc.state.counts, {'ראשון': 2, 'שני': 2});
        expect(bloc.state.total, 4);
        expect(bloc.state.countsByPath, {'ראשון': 2, 'שני': 2});
        expect(bloc.state.snippets.map((s) => s.path), ['ראשון', 'שני']);
        expect(bloc.state.snippets.map((s) => s.globalIndex), [0, 2]);
        expect(bloc.state.snippets.first.snippet, contains('וַיֹּאמֶר'));
      },
    );

    blocTest<CommentarySearchBloc, CommentarySearchState>(
      'החלפת שאילתה מבטלת await ישן כבר בזמן ה-debounce הבא',
      build: build,
      act: (bloc) async {
        final content = Completer<String>();
        final link = _Link('מושהה', content.future);
        bloc.add(request([link], 'ישן'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(request([link], 'חדש'));
        await Future<void>.delayed(Duration.zero);
        content.complete('ישן ישן ישן חדש');
      },
      wait: const Duration(milliseconds: 550),
      expect: () => [
        isA<CommentarySearchState>().having((s) => s.total, 'total', 0),
        isA<CommentarySearchState>().having((s) => s.total, 'total', 0),
        isA<CommentarySearchState>().having((s) => s.total, 'total', 1),
      ],
    );

    blocTest<CommentarySearchBloc, CommentarySearchState>(
      'תחום ריק מבטל טעינה ודיווח ישנים ומנקה גם קטעי חיפוש',
      build: build,
      act: (bloc) async {
        final content = Completer<String>();
        final link = _Link('נמחק', content.future);
        bloc.add(request([link], 'אמר'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final generation = bloc.generation;
        bloc.add(request([], 'אמר'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          CommentarySearchReported(
            generation: generation,
            key: link.path2,
            count: 9,
            snippets: ['ישן'],
          ),
        );
        content.complete('אמר אמר');
      },
      wait: const Duration(milliseconds: 550),
      verify: (bloc) {
        expect(bloc.state.total, 0);
        expect(bloc.state.counts, isEmpty);
        expect(bloc.state.countsByPath, isEmpty);
        expect(bloc.state.snippets, isEmpty);
      },
    );

    blocTest<CommentarySearchBloc, CommentarySearchState>(
      'שינוי פרופיל באותה שאילתה מחליף קטע גם כשמספר ההתאמות נשאר זהה',
      build: build,
      act: (bloc) async {
        final link = _Link('ניקוד', Future.value('אָמַר אָמַר'));
        bloc.add(request([link], 'אמר'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(bloc.state.total, 2);
        expect(bloc.state.snippets.single.snippet, contains('אָמַר'));
        bloc.add(
          request(
            [link],
            'אמר',
            profile: TextDisplayProfile.defaults.copyWith(
              nikud: MarkVisibility.hide,
            ),
          ),
        );
      },
      wait: const Duration(milliseconds: 550),
      verify: (bloc) {
        expect(bloc.state.total, 2);
        expect(bloc.state.snippets.single.snippet, contains('אמר אמר'));
        expect(bloc.state.snippets.single.snippet, isNot(contains('אָמַר')));
      },
    );

    blocTest<CommentarySearchBloc, CommentarySearchState>(
      'שינוי סדר עם אותם מפתחות משנה את היסטי הקטעים',
      build: build,
      act: (bloc) async {
        final first = _Link('ראשון', Future.value('אמר אמר'));
        final second = _Link('שני', Future.value('אמר'));
        bloc.add(request([first, second], 'אמר'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(bloc.state.snippets.map((s) => s.globalIndex), [0, 2]);
        bloc.add(request([second, first], 'אמר'));
      },
      wait: const Duration(milliseconds: 550),
      verify: (bloc) {
        expect(bloc.state.total, 3);
        expect(bloc.state.snippets.map((s) => s.path), ['שני', 'ראשון']);
        expect(bloc.state.snippets.map((s) => s.globalIndex), [0, 1]);
      },
    );

    blocTest<CommentarySearchBloc, CommentarySearchState>(
      'דיווחים מרונדרים מתפרסמים באותו flush בלי לשנות סכום כולל',
      build: build,
      act: (bloc) async {
        bloc.add(
          request([
            _Link('ראשון', Future.value('אמר אמר')),
            _Link('שני', Future.value('אמר אמר')),
          ], 'אמר'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        bloc.add(
          CommentarySearchReported(
            generation: bloc.generation,
            key: 'ראשון',
            count: 3,
          ),
        );
        bloc.add(
          CommentarySearchReported(
            generation: bloc.generation,
            key: 'שני',
            count: 1,
          ),
        );
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) {
        expect(bloc.state.total, 4);
        expect(bloc.state.snippets.map((s) => s.globalIndex), [0, 3]);
      },
    );

    test('סגירה מבטלת טעינה וטיימרים בלי לדווח ל-bloc סגור', () async {
      final bloc = build();
      final content = Completer<String>();
      bloc.add(request([_Link('סגירה', content.future)], 'אמר'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await bloc.close();
      content.complete('אמר');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.total, 0);
    });
  }, skip: !engineReady);
}

class _Link extends Link {
  final Future<String> _content;
  _Link(String path, this._content)
    : super(
        heRef: path,
        index1: 1,
        path2: path,
        index2: 1,
        connectionType: 'COMMENTARY',
      );

  @override
  Future<String> get content => _content;
}
