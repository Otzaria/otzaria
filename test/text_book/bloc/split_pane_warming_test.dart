import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// סופר בקשות טעינת טווח — כך נמדד אם החימום ברקע פעיל.
class _CountingRepository extends TextBookRepository {
  _CountingRepository() : super(fileSystem: FileSystemData.instance);

  int rangeRequests = 0;

  @override
  Future<String> getBookContent(TextBook book) async =>
      List.generate(6000, (i) => 'שורה $i').join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    rangeRequests++;
    return super.getBookContentRange(
      book,
      startLine: startLine,
      endLine: endLine,
    );
  }
}

/// חימום מטמון התוכן טוען את הספר כולו. בטאב מפוצל כמה חלוניות היו מחממות
/// ספרים גדולים במקביל — ולכן הוא מכובה שם דרך [SetTabVisibility].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingRepository repository;
  late TextBookBloc bloc;
  late TextBook book;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    repository = _CountingRepository();
    bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 10, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  TextBookLoaded seeded() => TextBookLoaded(
    book: book,
    content: const ['שורה'],
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [10],
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );

  test('כיבוי החימום נקלט גם כשהנראות אינה משתנה', () async {
    bloc.emit(seeded());

    // הנראות נשארת true בשני האירועים: בלי בדיקת דגל החימום, האירוע השני
    // היה נבלע ע"י ה-early return והחימום היה ממשיך בכל החלוניות.
    bloc.add(const SetTabVisibility(true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final afterWarming = repository.rangeRequests;

    bloc.add(const SetTabVisibility(true, allowBackgroundWarming: false));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      repository.rangeRequests,
      lessThanOrEqualTo(afterWarming + 1),
      reason: 'החימום נעצר אחרי כיבוי הדגל',
    );
  });

  test('ברירת המחדל מאפשרת חימום', () {
    const event = SetTabVisibility(true);
    expect(event.allowBackgroundWarming, isTrue);
  });

  test('הדגל משתתף בהשוואת האירועים', () {
    expect(
      const SetTabVisibility(true),
      isNot(const SetTabVisibility(true, allowBackgroundWarming: false)),
    );
    expect(
      const SetTabVisibility(true, allowBackgroundWarming: false),
      const SetTabVisibility(true, allowBackgroundWarming: false),
    );
  });
}
