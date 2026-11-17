import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/recent_book_opens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// התוכן נכשל, או לא חוזר כלל כש-[hang].
class _ContentRepository extends TextBookRepository {
  _ContentRepository({this.hang = false})
    : super(fileSystem: FileSystemData.instance);

  final bool hang;
  final Completer<BookContentRange?> _never = Completer();

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) => hang ? _never.future : throw StateError('content unavailable');

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];
}

typedef _Entry = ({String title, Object error, Map<String, String?> details});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDataRoot;
  late List<_Entry> written;
  late RecentBookOpens previous;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    tempDataRoot = Directory.systemTemp.createTempSync('book-load-diag-');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
    written = [];
    previous = RecentBookOpens.instance;
  });

  tearDown(() {
    RecentBookOpens.instance = previous;
    AppPaths.debugOverrideDataRootPath(null);
    if (tempDataRoot.existsSync()) tempDataRoot.deleteSync(recursive: true);
  });

  RecentBookOpens install({Duration? stallThreshold}) =>
      RecentBookOpens.instance = RecentBookOpens(
        stallThreshold: stallThreshold,
        writeLog:
            ({
              required String title,
              required Object error,
              StackTrace? stackTrace,
              Map<String, String?> details = const {},
            }) => written.add((title: title, error: error, details: details)),
      );

  TextBookBloc open(TextBookRepository repository, TextBook book) {
    final bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 12, false, const []),
    );
    addTearDown(bloc.close);
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    return bloc;
  }

  test('כשל בטעינת ספר נרשם ל-errors.txt ולניסיונות הפתיחה', () async {
    final opens = install();
    final book = TextBook(title: 'ספר בדיקה', id: 42, source: BookSource.user);
    final bloc = open(_ContentRepository(), book);

    await bloc.stream
        .firstWhere((s) => s is TextBookError)
        .timeout(const Duration(seconds: 10));

    final entry = written.single;
    expect(entry.title, 'Book Load Error (text)');
    expect(entry.error, isA<StateError>());
    expect(entry.details, containsPair('book', 'ספר בדיקה'));
    expect(entry.details, containsPair('id', '42'));
    expect(entry.details, containsPair('source', 'u'));
    expect(entry.details, containsPair('index', '12'));
    expect(opens.attempts.single.outcome, BookOpenOutcome.failed);
  });

  test('טעינה שלא מסתיימת נרשמת פעם אחת, וסגירה מבטלת את הטיימר', () async {
    final opens = install(stallThreshold: const Duration(milliseconds: 50));
    final bloc = open(_ContentRepository(hang: true), TextBook(title: 'תקוע'));

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (written.isEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('התקיעה לא נרשמה');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(bloc.state, isA<TextBookLoading>());
    expect(written.single.title, 'Book Load Stalled');
    expect(written.single.details, containsPair('book', 'תקוע'));
    expect(opens.attempts.single.outcome, BookOpenOutcome.stalled);

    await bloc.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(written, hasLength(1));
    expect(opens.attempts.single.isFinished, isTrue);
  });

  test('סגירה לפני הסף מבטלת את הטיימר בלי רשומה', () async {
    final opens = install(stallThreshold: const Duration(milliseconds: 100));
    final bloc = open(_ContentRepository(hang: true), TextBook(title: 'נסגר'));
    await bloc.stream.firstWhere((s) => s is TextBookLoading);

    await bloc.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(written, isEmpty);
    expect(opens.attempts.single.outcome, BookOpenOutcome.closed);
  });
}
