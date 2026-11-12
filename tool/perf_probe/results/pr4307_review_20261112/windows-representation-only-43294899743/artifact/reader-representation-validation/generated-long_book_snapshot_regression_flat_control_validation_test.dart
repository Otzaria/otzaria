// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('טווחים חופפים שומרים snapshots קודמים ואת שורות המקור', () async {
    final book = _book();
    final bloc = _bloc(book, repository: _RangeRepository(lineCount: 4096));
    await _open(bloc);

    final firstInput = ['שָׁלוֹם', 'תוכן \u2066abc\u2069', '', 'א\u0301ב'];
    await bloc.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 638,
        totalLines: 4096,
        lines: firstInput,
      ),
    );
    final first = bloc.state as TextBookLoaded;
    final firstCopy = first.content.sublist(638, 642);
    firstInput[0] = 'קלט ששונה לאחר השליחה';

    await bloc.dispatch(
      ApplyBookContentRanges(
        bookTitle: book.title,
        ranges: [
          (startLine: 639, totalLines: 4096, lines: ['חדש', '']),
          (startLine: 1023, totalLines: 4096, lines: ['ימין', 'שמאל']),
        ],
      ),
    );
    final second = bloc.state as TextBookLoaded;

    expect(first.content.sublist(638, 642), firstCopy);
    expect(first.content[1023], isEmpty);
    expect(first.isContentLineLoaded(1023), isFalse);
    expect(second.content.sublist(638, 642), [
      'שָׁלוֹם',
      'חדש',
      '',
      'א\u0301ב',
    ]);
    expect(second.content.sublist(1023, 1025), ['ימין', 'שמאל']);
    expect(second.content.length, 4096);
    expect(second.isContentLineLoaded(640), isTrue);
    expect(second.isContentLineLoaded(642), isFalse);
    expect(second.contentVersion, first.contentVersion + 1);
    expect(second.contentChanges?.fromVersion, first.contentVersion);
    expect(second.contentChanges?.ranges, [
      (first: 639, last: 640),
      (first: 1023, last: 1024),
    ]);
    expect(() => second.loadedLineFlags![639] = false, throwsUnsupportedError);
  });

  test('שורה ריקה טעונה מתעדכנת פעם אחת ולא נחשבת placeholder', () async {
    final book = _book();
    final bloc = _bloc(book, repository: _RangeRepository(lineCount: 2048));
    await _open(bloc);
    final before = bloc.state as TextBookLoaded;
    final event = ApplyBookContentRange(
      bookTitle: book.title,
      startLine: 1024,
      totalLines: 2048,
      lines: const [''],
    );

    await bloc.dispatch(event);
    final loaded = bloc.state as TextBookLoaded;
    expect(loaded.content[1024], isEmpty);
    expect(loaded.isContentLineLoaded(1024), isTrue);
    expect(loaded.isContentLineLoaded(1025), isFalse);
    expect(loaded.contentVersion, before.contentVersion + 1);

    await bloc.dispatch(event);
    expect(bloc.state, same(loaded));
  });

  test('טווחים זהים אחרי תוכן מלא בודקים רק את שורות הטווח', () async {
    const lineCount = 16384;
    final book = _book();
    final bloc = _bloc(book);
    final values = List.generate(
      lineCount,
      (line) => line == 0 || line == lineCount - 2 ? '' : 'שׁוּרָה $line',
    );
    final source = _ReadCountingLines(values);
    bloc.emit(_loaded(book, const []));
    await bloc.dispatch(
      ApplyFullBookContent(bookTitle: book.title, content: source),
    );
    final full = bloc.state as TextBookLoaded;
    expect(full.content, same(source));
    expect(full.isContentLineLoaded(0), isTrue);
    expect(full.isContentLineLoaded(lineCount - 2), isTrue);
    final tail = values.sublist(lineCount - 640);
    final requests = <({TextBookEvent event, int checkedLines})>[
      (
        event: ApplyBookContentRange(
          bookTitle: book.title,
          startLine: lineCount - 640,
          totalLines: lineCount,
          lines: tail,
        ),
        checkedLines: 640,
      ),
      (
        event: ApplyBookContentRanges(
          bookTitle: book.title,
          ranges: [
            (
              startLine: -2,
              totalLines: lineCount,
              lines: ['נחתך', 'נחתך', ...values.take(3)],
            ),
            (
              startLine: lineCount - 640,
              totalLines: lineCount,
              lines: tail,
            ),
          ],
        ),
        checkedLines: 643,
      ),
      (
        event: ApplyBookContentRange(
          bookTitle: book.title,
          startLine: -5,
          totalLines: lineCount,
          lines: const ['מחוץ לספר', 'מחוץ לספר'],
        ),
        checkedLines: 0,
      ),
    ];

    for (var repetition = 0; repetition < 3; repetition++) {
      for (final request in requests) {
        source.reads = 0;
        await bloc.dispatch(request.event);
        expect(source.reads, lessThanOrEqualTo(request.checkedLines));
        final after = bloc.state as TextBookLoaded;
        expect(after, same(full));
        expect(after.content, same(source));
        expect(after.loadedLineFlags, same(full.loadedLineFlags));
        expect(after.contentVersion, full.contentVersion);
        expect(after.contentChanges, same(full.contentChanges));
      }
    }

    // גם טווח זהה מאשר תמיכה בטעינת טווחים לצורך פינוי טאב מוסתר.
    await bloc.dispatch(const SetTabVisibility(false));
    final hidden = bloc.state as TextBookLoaded;
    expect(hidden.content.length, lineCount);
    expect(hidden.isContentLineLoaded(lineCount - 2), isFalse);
    expect(hidden.content[lineCount - 1], isEmpty);
    expect(full.content[lineCount - 1], values.last);
  });

  for (final extendsBook in [false, true]) {
    test('טווח אחרי תוכן מלא מחיל שינוי אמיתי (הארכה=$extendsBook)', () async {
      final book = _book();
      final bloc = _bloc(book);
      final source = List.generate(2048, (line) => 'שׁוּרָה $line');
      bloc.emit(_loaded(book, const []));
      await bloc.dispatch(
        ApplyFullBookContent(bookTitle: book.title, content: source),
      );
      final full = bloc.state as TextBookLoaded;
      final start = source.length - 1;
      final lines = extendsBook ? [source.last, ''] : ['תוכן שהשתנה'];

      await bloc.dispatch(
        ApplyBookContentRange(
          bookTitle: book.title,
          startLine: start,
          totalLines: start + lines.length,
          lines: lines,
        ),
      );
      final updated = bloc.state as TextBookLoaded;
      expect(updated.content.length, start + lines.length);
      expect(updated.content.sublist(start), lines);
      expect(updated.loadedLineFlags!.length, updated.content.length);
      expect(updated.isContentLineLoaded(updated.content.length - 1), isTrue);
      expect(updated.contentVersion, full.contentVersion + 1);
      expect(updated.contentChanges?.fromVersion, full.contentVersion);
      expect(updated.contentChanges?.ranges, [
        (first: start, last: start + lines.length - 1),
      ]);
      expect(full.content, same(source));
      expect(full.content.length, 2048);
      expect(full.content.last, 'שׁוּרָה 2047');
    });
  }

  test('תוכן זהה ללא דגלים טעונים עדיין מפרסם טעינת שורה ריקה', () async {
    final book = _book();
    final bloc = _bloc(book);
    bloc.emit(_loaded(book, const ['א', '', 'ג']));
    final before = bloc.state as TextBookLoaded;

    await bloc.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 1,
        totalLines: 3,
        lines: const [''],
      ),
    );
    final updated = bloc.state as TextBookLoaded;
    expect(updated.content, ['א', '', 'ג']);
    expect(updated.loadedLineFlags, [false, true, false]);
    expect(updated.isContentLineLoaded(1), isTrue);
    expect(updated.contentVersion, before.contentVersion + 1);
    expect(before.loadedLineFlags, isNull);
  });

  test('טווחים שמשנים ואז משחזרים תוכן מלא שומרים על עדכון revision', () async {
    final book = _book();
    final bloc = _bloc(book);
    const source = ['א', '', 'ג'];
    bloc.emit(_loaded(book, const []));
    await bloc.dispatch(
      ApplyFullBookContent(bookTitle: book.title, content: source),
    );
    final full = bloc.state as TextBookLoaded;

    await bloc.dispatch(
      ApplyBookContentRanges(
        bookTitle: book.title,
        ranges: const [
          (startLine: 1, totalLines: 3, lines: ['תוכן זמני']),
          (startLine: 1, totalLines: 3, lines: ['']),
        ],
      ),
    );
    final updated = bloc.state as TextBookLoaded;
    expect(updated.content, source);
    expect(updated.contentVersion, full.contentVersion + 1);
    expect(updated.contentChanges?.fromVersion, full.contentVersion);
    expect(full.content, same(source));
  });

  test('טווחים מחוץ לגבולות שומרים offset ומרחיבים אינדקסים לוגיים', () async {
    final book = _book();
    final bloc = _bloc(book, repository: _RangeRepository(lineCount: 2048));
    await _open(bloc);
    final original = bloc.state as TextBookLoaded;

    await bloc.dispatch(
      ApplyBookContentRanges(
        bookTitle: book.title,
        ranges: const [
          (
            startLine: -2,
            totalLines: 2048,
            lines: ['נחתך', 'נחתך', 'א', 'ב', ''],
          ),
          (startLine: 2047, totalLines: 2050, lines: ['קצה', 'תוספת', '']),
        ],
      ),
    );
    final updated = bloc.state as TextBookLoaded;

    expect(updated.content.length, 2050);
    expect(updated.loadedLineFlags!.length, 2050);
    expect(updated.content.sublist(0, 3), ['א', 'ב', '']);
    expect(updated.content[3], original.content[3]);
    expect(updated.content.sublist(2047, 2050), ['קצה', 'תוספת', '']);
    expect(updated.isContentLineLoaded(2046), isFalse);
    for (final line in [0, 1, 2, 2047, 2048, 2049]) {
      expect(updated.isContentLineLoaded(line), isTrue);
    }
    expect(updated.contentVersion, original.contentVersion + 1);
    expect(original.content.length, 2048);
    expect(original.content[0], isNot('א'));
    expect(original.content[2047], isEmpty);

    await bloc.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: -4,
        totalLines: 2050,
        lines: const ['מחוץ לספר', 'מחוץ לספר'],
      ),
    );
    expect(bloc.state, same(updated));
  });

  test('פסקה רציפה חוצה מקטעים בלי לשנות ניקוד, UTF-16 ואינדקסים', () async {
    final book = _book();
    final bloc = _bloc(book);
    final source = List.generate(1400, (i) => 'שׁוּרָה $i \u2066abc\u2069');
    bloc.emit(_loaded(book, const []));
    await bloc.dispatch(
      ApplyFullBookContent(bookTitle: book.title, content: source),
    );
    await bloc.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 767,
        totalLines: source.length,
        lines: const ['נִקּוּד e\u0301', 'טקסט \u{1F600}', '', 'סוֹף'],
      ),
    );
    final state = (bloc.state as TextBookLoaded).copyWith(
      supportsContinuousReadingMode: true,
      continuousReadingMode: true,
      selectedIndex: 768,
      selectedIndices: const {768, 769, 770},
      highlightText: 'טקסט',
      permanentHighlightLine: 768,
    );
    final segments = readingSegmentsOf(state);
    final item = segments.layout.itemForLine(768);
    final segment = segments[item];

    expect(segment.isLoaded, isTrue);
    expect(segment.sourceLineIndices, containsAllInOrder([767, 768, 769, 770]));
    for (final range in segment.lineRanges) {
      expect(
        segment.text.substring(range.start, range.end),
        state.content[range.lineIndex].trim(),
      );
    }
    expect(segments.layout.itemForLine(769), item);
    expect(state.selectedIndices, {768, 769, 770});
    expect(state.isHighlightYellowBackground(768), isTrue);
    expect(state.content[768], 'טקסט \u{1F600}');
    expect(source[768], 'שׁוּרָה 768 \u2066abc\u2069');
  });

  test('חלוניות עם אותו ספר אינן משנות snapshots זו של זו', () async {
    final book = _book();
    final first = _bloc(book, repository: _RangeRepository(lineCount: 4096));
    final second = _bloc(book, repository: _RangeRepository(lineCount: 4096));
    await _open(first);
    await _open(second);
    final seed = first.state as TextBookLoaded;
    await first.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 1023,
        totalLines: 4096,
        lines: const ['חלון ראשון', 'גבול'],
      ),
    );
    final firstSnapshot = first.state as TextBookLoaded;
    await second.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 1024,
        totalLines: 4096,
        lines: const ['חלון שני'],
      ),
    );

    expect(firstSnapshot.content[1024], 'גבול');
    expect((second.state as TextBookLoaded).content[1023], isEmpty);
    expect((second.state as TextBookLoaded).content[1024], 'חלון שני');
    expect(seed.content[1023], isEmpty);
    expect(seed.content[1024], isEmpty);
    await first.dispatch(const SetTabVisibility(false));
    expect((second.state as TextBookLoaded).content[1024], 'חלון שני');
  });

  test('הטעינה הראשונה משלימה פסקה רציפה ושינוי גופן שומר תוכן', () async {
    await Settings.setValue<bool>('key-continuous-reading-mode', true);
    final book = _book();
    final repository = _RangeRepository();
    final bloc = _bloc(book, repository: repository, initialIndex: 799);
    await bloc.dispatch(
      const SetTabVisibility(true, allowBackgroundWarming: false),
    );
    await bloc.dispatch(_load);
    final initial = bloc.state as TextBookLoaded;
    final initialContent = initial.content;
    final layout = readingLayoutOf(initial);
    final item = layout.itemForLine(799);

    expect(initial.content.length, repository.lineCount);
    expect(initial.visibleIndices.first, 799);
    expect(initial.continuousReadingMode, isTrue);
    expect(repository.requests, contains((startLine: 601, endLine: 800)));
    for (var i = layout.firstLineOf(item); i <= layout.lastLineOf(item); i++) {
      expect(initial.isContentLineLoaded(i), isTrue);
      expect(initial.content[i], repository.lineAt(i));
    }
    expect(initial.isContentLineLoaded(5000), isFalse);
    expect(repository.fullReads, 0);

    await bloc.dispatch(
      const LoadContent(
        fontSize: 31,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
        preserveState: true,
        preserveRemoveNikud: true,
        preserveContinuousReadingMode: true,
      ),
    );
    final resized = bloc.state as TextBookLoaded;
    expect(resized.fontSize, 31);
    expect(resized.visibleIndices.first, 799);
    expect(resized.content[799], initialContent[799]);
    expect(resized.continuousReadingMode, isTrue);
    expect(initialContent[601], repository.lineAt(601));
    expect(repository.fullReads, 0);
  });

  test('סגירה בזמן קריאת טווח לא מחילה תוכן שהגיע באיחור', () async {
    final book = _book();
    final repository = _RangeRepository();
    final bloc = _bloc(book, repository: repository);
    await bloc.dispatch(
      const SetTabVisibility(true, allowBackgroundWarming: false),
    );
    bloc.emit(_loaded(book, List.filled(repository.lineCount, '')));
    final gate = repository.blockNextRange();
    await bloc.dispatch(const UpdateVisibleIndecies([3000]));
    await gate.started.future;
    final beforeClose = bloc.state as TextBookLoaded;

    await bloc.close();
    final closedState = bloc.state as TextBookLoaded;
    gate.release.complete();
    await gate.completed.future;
    await pumpEventQueue();

    expect(bloc.isClosed, isTrue);
    expect(bloc.state, same(closedState));
    expect(closedState.content, same(beforeClose.content));
    expect(closedState.contentVersion, beforeClose.contentVersion);
    expect(closedState.loadedLineFlags, same(beforeClose.loadedLineFlags));
    expect(closedState.content[3000], isEmpty);
  });

  test('טעינה מחדש בשינוי גופן לא דורסת טווח שהגיע בזמן ההמתנה', () async {
    final book = _book();
    final repository = _RangeRepository();
    final bloc = _bloc(book, repository: repository);
    await bloc.dispatch(
      const SetTabVisibility(true, allowBackgroundWarming: false),
    );
    bloc.emit(_loaded(book, List.filled(repository.lineCount, '')));
    await bloc.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 10,
        totalLines: repository.lineCount,
        lines: const ['תוכן קודם'],
      ),
    );
    final before = bloc.state as TextBookLoaded;
    final gate = repository.blockNextSupportCheck();
    final refreshedState = bloc.stream
        .where((state) => state is TextBookLoaded && state.fontSize == 32)
        .cast<TextBookLoaded>()
        .first;
    final reloading = bloc.dispatch(
      const LoadContent(
        fontSize: 32,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
        preserveState: true,
        preserveRemoveNikud: true,
      ),
    );
    await gate.started.future;
    await bloc.dispatch(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 8000,
        totalLines: repository.lineCount,
        lines: const ['טווח חדש בזמן שינוי גופן'],
      ),
    );
    final during = bloc.state as TextBookLoaded;
    gate.release.complete();
    await reloading;
    final after = await refreshedState;

    expect(after.fontSize, 32);
    expect(after.content[8000], 'טווח חדש בזמן שינוי גופן');
    expect(after.isContentLineLoaded(8000), isTrue);
    expect(after.contentVersion, greaterThan(before.contentVersion));
    expect(after.contentVersion, during.contentVersion);
    expect(after.content, same(during.content));
    expect(after.contentChanges, same(during.contentChanges));
    expect(before.content[8000], isEmpty);
  });

  for (final continuous in [false, true]) {
    test(
      'סגירה בזמן פתיחה (רציף=$continuous) אינה מחזירה listener או I/O',
      () async {
        await Settings.setValue<bool>(
          'key-continuous-reading-mode',
          continuous,
        );
        final book = _book();
        final repository = _RangeRepository();
        final position = _TrackedPosition();
        addTearDown(position.dispose);
        final bloc = _bloc(
          book,
          repository: repository,
          initialIndex: 799,
          readingPosition: position,
        );
        final gate = repository.blockNextRange();
        final loading = bloc.dispatch(_load);
        await gate.started.future;

        await bloc.close();
        final requestsAtClose = repository.requests.length;
        gate.release.complete();
        await loading;
        await pumpEventQueue();

        expect(bloc.isClosed, isTrue);
        expect(position.listenerCount, 0);
        expect(repository.requests.length, requestsAtClose);
      },
    );
  }

  test(
    'כשל metadata מאוחר אחרי סגירה אינו נשאר Future error לא מטופל',
    () async {
      final book = _book();
      final repository = _RangeRepository();
      final protection = Completer<BookProtection>();
      final bloc = _bloc(
        book,
        repository: repository,
        protectionLoader: (_) => protection.future,
      );
      final gate = repository.blockNextRange();
      final loading = bloc.dispatch(_load);
      await gate.started.future;

      await bloc.close();
      gate.release.complete();
      await loading;
      protection.completeError(StateError('Cancelled metadata request'));
      await pumpEventQueue();

      expect(bloc.isClosed, isTrue);
    },
  );
}

const _load = LoadContent(
  fontSize: 20,
  showSplitView: false,
  removeNikud: false,
  loadCommentators: false,
);

TextBook _book() => TextBook(
  id: 123,
  title: 'ספר בדיקת מקטעים',
  source: BookSource.user,
  heCategories: 'בדיקות',
  author: 'מחבר בדיקה',
);

_ObservedBloc _bloc(
  TextBook book, {
  _RangeRepository? repository,
  int initialIndex = 0,
  ValueListenable<ReadingPosition?>? readingPosition,
  Future<BookProtection> Function(Book book)? protectionLoader,
}) {
  final bloc = _ObservedBloc(
    repository: repository ?? _RangeRepository(),
    initialState: TextBookInitial.named(book, initialIndex, false, const []),
    protectionLoader: protectionLoader ?? (_) async => BookProtection.none,
    bookNotesLoader: (_) async => BookNotes.empty,
    readingPosition: readingPosition,
  );
  addTearDown(() async {
    if (!bloc.isClosed) await bloc.close();
  });
  return bloc;
}

Future<void> _open(_ObservedBloc bloc) async {
  await bloc.dispatch(
    const SetTabVisibility(true, allowBackgroundWarming: false),
  );
  await bloc.dispatch(_load);
  await pumpEventQueue();
}

TextBookLoaded _loaded(TextBook book, List<String> content) => TextBookLoaded(
  book: book,
  content: content,
  fontSize: 20,
  showLeftPane: false,
  showSplitView: false,
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
);

class _ReadCountingLines extends ListBase<String> {
  _ReadCountingLines(this._values);

  final List<String> _values;
  int reads = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('Read-only source');

  @override
  String operator [](int index) {
    reads++;
    return _values[index];
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('Read-only source');
}

class _ObservedBloc extends TextBookBloc {
  _ObservedBloc({
    required super.repository,
    required super.initialState,
    super.protectionLoader,
    super.bookNotesLoader,
    super.readingPosition,
  });

  final _pending = Map<TextBookEvent, Completer<void>>.identity();

  Future<void> dispatch(TextBookEvent event) {
    final done = Completer<void>();
    _pending[event] = done;
    add(event);
    return done.future.timeout(const Duration(seconds: 10));
  }

  @override
  void onDone(TextBookEvent event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(event, error, stackTrace);
    final done = _pending.remove(event);
    if (done == null) return;
    if (error == null) {
      done.complete();
    } else {
      done.completeError(error, stackTrace);
    }
  }
}

class _RangeGate {
  final started = Completer<void>();
  final release = Completer<void>();
  final completed = Completer<void>();
}

class _RangeRepository extends TextBookRepository {
  _RangeRepository({this.lineCount = 10000})
    : super(fileSystem: FileSystemData.instance);

  final int lineCount;
  final requests = <({int startLine, int endLine})>[];
  var fullReads = 0;
  _RangeGate? _nextGate;
  _RangeGate? _nextSupportGate;

  String lineAt(int line) => 'שׁוּרָה $line';

  _RangeGate blockNextRange() => _nextGate = _RangeGate();

  _RangeGate blockNextSupportCheck() => _nextSupportGate = _RangeGate();

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    requests.add((startLine: startLine, endLine: endLine));
    final gate = _nextGate;
    _nextGate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    final first = startLine.clamp(0, lineCount - 1);
    final last = endLine.clamp(first, lineCount - 1);
    final result = BookContentRange(
      startLine: first,
      endLine: last,
      totalLines: lineCount,
      lines: [for (var i = first; i <= last; i++) lineAt(i)],
    );
    gate?.completed.complete();
    return result;
  }

  @override
  Future<String> getBookContent(TextBook book) async {
    fullReads++;
    return List.generate(lineCount, lineAt).join('\n');
  }

  @override
  Future<bool> supportsContinuousReadingMode(TextBook book) async {
    final gate = _nextSupportGate;
    _nextSupportGate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
      gate.completed.complete();
    }
    return true;
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => [
    TocEntry(text: 'פתיחה', index: 0),
    TocEntry(text: 'המשך', index: 2000),
  ];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}

class _TrackedPosition extends ValueNotifier<ReadingPosition?> {
  _TrackedPosition() : super(null);

  var listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (hasListeners) listenerCount--;
    super.removeListener(listener);
  }
}
