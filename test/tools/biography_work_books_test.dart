import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tools/biographies/biographies_screen.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';
import 'package:otzaria/tools/tool_query.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';
import 'biographies_codec_test.dart' show encodeBundle, samplePayload;

/// Library books of the official catalog (version 39) behind the failures
/// reported when PR #5660 was closed.
TextBook _book(
  String title,
  String author, {
  BookSource source = BookSource.official,
}) => TextBook(title: title, author: author, source: source);

final _yesodeiHatorah = _book(
  'פרי חדש על משנה תורה, הלכות יסודי התורה',
  'חזקיה די סילוה',
);
final _chovotHalevavot = _book('חובות הלבבות', 'בחיי אבן פקודה');

const _priChadash = BiographyWork(
  title: 'פרי חדש',
  description: 'חיבור הלכה על השולחן ערוך, בעיקר אורח חיים ויורה דעה',
);
const _chovot = BiographyWork(title: 'חובות הלבבות', books: ['חובות הלבבות']);

class _WorkRepository extends BiographiesRepository {
  _WorkRepository({required super.libraryBooks});

  @override
  Future<BiographiesBundle> loadBundle() async => const BiographiesBundle(
    eras: [],
    entries: [
      Biography(id: 'Q762229', name: 'רבינו בחיי אבן פקודה', works: [_chovot]),
    ],
  );
}

class _TestLibraryBloc extends Cubit<LibraryState> implements LibraryBloc {
  _TestLibraryBloc() : super(LibraryState(library: Library(categories: [])));

  void update(LibraryState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('biography works link to library books (issue #5203)', () {
    test('a work carries the book titles mapped in the bundle', () {
      final payload = samplePayload();
      ((payload['entries'] as List).first as Map)['works'] = [
        {
          'title': 'חובות הלבבות',
          'description': 'מיסודות ספרי המוסר',
          'books': ['חובות הלבבות'],
        },
        {'title': 'פרי חדש'},
      ];
      final works = BiographiesCodec.decode(
        encodeBundle(payload),
      ).entries.first.works;
      expect(works.first.books, ['חובות הלבבות']);
      expect(works.last.books, isEmpty);
    });

    test('"פרי חדש" on the Shulchan Arukh does not open the commentary on '
        'Mishneh Torah by the same author', () async {
      final repo = BiographiesRepository(
        libraryBooks: () async => [
          _yesodeiHatorah,
          _book('פרי חדש על משנה תורה, הלכות דעות', 'חזקיה די סילוה'),
        ],
      );
      final books = await repo.libraryBooksByTitle();
      expect(BiographiesRepository.bookForWork(_priChadash, books), isNull);
    });

    test('"חובות הלבבות" opens its mapped book, whatever the catalog '
        'author is called', () async {
      final repo = BiographiesRepository(
        libraryBooks: () async => [_yesodeiHatorah, _chovotHalevavot],
      );
      final books = await repo.libraryBooksByTitle();
      expect(
        BiographiesRepository.bookForWork(_chovot, books),
        same(_chovotHalevavot),
      );
    });

    test('a mapped title that names several library books has no link, and '
        'personal books are not candidates', () async {
      final repo = BiographiesRepository(
        libraryBooks: () async => [
          _chovotHalevavot,
          _book('חובות הלבבות', 'אחר'),
          _book('מסילת ישרים', 'משה חיים לוצאטו', source: BookSource.user),
        ],
      );
      final books = await repo.libraryBooksByTitle();
      expect(BiographiesRepository.bookForWork(_chovot, books), isNull);
      expect(
        BiographiesRepository.bookForWork(
          const BiographyWork(title: 'מסילת ישרים', books: ['מסילת ישרים']),
          books,
        ),
        isNull,
      );
    });

    test('a work of several volumes opens the first one in the library', () {
      final second = _book('ספר חלק ב', 'מחבר');
      expect(
        BiographiesRepository.bookForWork(
          const BiographyWork(title: 'ספר', books: ['ספר חלק א', 'ספר חלק ב']),
          {second.title: second},
        ),
        same(second),
      );
    });

    testWidgets('library refresh discards obsolete work links and requests', (
      tester,
    ) async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      final libraryBloc = _TestLibraryBloc();
      final settingsBloc = StubSettingsBloc();
      final inbox = ToolQueryInbox()
        ..post(const ToolQuery.biography('Q762229'));
      final data = DataRepository.instance;
      final previousCatalog = data.cachedLibraryFutureForTesting;
      addTearDown(() {
        if (previousCatalog == null) {
          data.invalidateLibraryCache();
        } else {
          data.library = previousCatalog;
        }
      });
      final requests = <Completer<List<Book>>>[];
      final repository = _WorkRepository(
        libraryBooks: () {
          final request = Completer<List<Book>>();
          requests.add(request);
          return request.future;
        },
      );

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<LibraryBloc>.value(value: libraryBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
              ],
              child: Scaffold(
                body: BiographiesScreen(
                  repository: repository,
                  queryInbox: inbox,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        BiographyCard card() => tester.widget(find.byType(BiographyCard));

        libraryBloc.update(const LibraryState(isLoading: true));
        final current = Library(categories: []);
        libraryBloc.update(LibraryState(library: current));
        await tester.pump();
        expect(requests, hasLength(2));
        requests.first.complete([_chovotHalevavot]);
        await tester.pump();
        expect(card().bookForWork(_chovot), isNull);

        final moved = _book('חובות הלבבות', 'בחיי אבן פקודה');
        requests.last.complete([moved]);
        await tester.pumpAndSettle();
        final oldCallback = card().onOpenBook!;
        expect(card().bookForWork(_chovot), same(moved));

        libraryBloc.update(LibraryState(library: current, isLoading: true));
        await tester.pump();
        expect(card().bookForWork(_chovot), isNull);
        expect(() => oldCallback(moved), returnsNormally);
        libraryBloc.update(LibraryState(library: current, error: 'לא זמין'));
        await tester.pump();
        expect(requests, hasLength(2));
        expect(card().bookForWork(_chovot), isNull);

        libraryBloc.update(LibraryState(library: Library(categories: [])));
        await tester.pump();
        expect(requests, hasLength(3));
        requests.last.complete([_chovotHalevavot]);
        await tester.pumpAndSettle();
        expect(card().bookForWork(_chovot), same(_chovotHalevavot));

        data.library = Future.value(Library(categories: []));
        expect(() => card().onOpenBook!(_chovotHalevavot), returnsNormally);
        await tester.pump();
        expect(requests, hasLength(4));
        requests.last.complete([]);
        await tester.pump();
        expect(card().bookForWork(_chovot), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await libraryBloc.close();
        // Bloc.close ממתין לביטול מנוי שההשלמה שלו מתוזמנת ב-zone האמיתי.
        await tester.runAsync(settingsBloc.close);
        inbox.dispose();
      }
    });

    testWidgets('the card links a mapped work only', (tester) async {
      Book? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: BiographyCard(
                  biography: const Biography(
                    id: 'Q762229',
                    name: 'רבינו בחיי בן יוסף אבן פקודה',
                    works: [_chovot, _priChadash],
                  ),
                  initiallyExpanded: true,
                  bookForWork: (work) =>
                      BiographiesRepository.bookForWork(work, {
                        _chovotHalevavot.title: _chovotHalevavot,
                        _yesodeiHatorah.title: _yesodeiHatorah,
                      }),
                  onOpenBook: (book) => opened = book,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final link = find.bySemanticsLabel('חובות הלבבות');
      expect(link, findsOneWidget);
      expect(tester.getSemantics(link), isSemantics(isLink: true));
      expect(find.bySemanticsLabel(RegExp('^פרי חדש\$')), findsNothing);

      await tester.tap(find.text('חובות הלבבות'));
      expect(opened, same(_chovotHalevavot));

      opened = null;
      await tester.tap(find.textContaining('פרי חדש'));
      expect(opened, isNull);
    });
  });
}
