import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _totalLines = 3000;
const _firstImageLine = 2000;

/// מחרוזת אחת משותפת לכל שורות התמונה, כך שהבדיקה עצמה אינה תופסת זיכרון.
final _heavyImageLine =
    '<img src="data:image/png;base64,${'A' * (4 * 1024 * 1024)}">';

String _line(int index) =>
    index >= _firstImageLine ? _heavyImageLine : 'שורה $index';

/// מסד מדומה שמכבד את maxChars ואת budgetFromEnd כמו ה-worker.
class _HeavyImagesRepository extends TextBookRepository {
  _HeavyImagesRepository() : super(fileSystem: FileSystemData.instance);

  int requests = 0;

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    requests++;
    final start = startLine.clamp(0, _totalLines - 1);
    final end = endLine.clamp(start, _totalLines - 1);
    final indices = [for (var i = start; i <= end; i++) i];
    final taken = <int>[];
    var chars = 0;
    for (final i in budgetFromEnd ? indices.reversed : indices) {
      taken.add(i);
      chars += _line(i).length;
      if (maxChars != null && chars >= maxChars) break;
    }
    taken.sort();
    return BookContentRange(
      startLine: taken.first,
      endLine: taken.last,
      totalLines: _totalLines,
      lines: [for (final i in taken) _line(i)],
    );
  }
}

void main() {
  late _HeavyImagesRepository repository;
  late TextBookBloc bloc;
  final book = TextBook(title: 'ספר תמונות');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    repository = _HeavyImagesRepository();
    bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 0, true, const []),
    );
  });

  tearDown(() => bloc.close());

  Future<void> settle(WidgetTester tester) async {
    // הבלוק נוצר מחוץ ל-FakeAsync, ולכן ההשהיות שבו רצות בזמן אמיתי.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('חלון התוכן סביב קטע תמונות מוטמעות נטען בתקרה ולא נטען שוב '
      'בכל גלילה', (tester) async {
    bloc.emit(
      TextBookLoaded(
        book: book,
        content: List<String>.filled(_totalLines, ''),
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
        visibleIndices: const [2500, 2501],
        pinLeftPane: false,
        searchText: '',
      ),
    );
    // בלי חימום: נמדד רק חלון התצוגה.
    bloc.add(const SetTabVisibility(true, allowBackgroundWarming: false));
    await settle(tester);

    var content = (bloc.state as TextBookLoaded).content;
    expect(content[2500], _heavyImageLine);
    expect(content[2501], _heavyImageLine);
    final loadedImages = content.where((line) => line.length > 1000).length;
    // שתי הגלויות ועוד כשתי שורות לכל צד, במקום ~380 שורות החלון.
    expect(loadedImages, lessThanOrEqualTo(8));

    // גלילה בתוך מה שכבר נטען אינה טוענת שוב.
    final requestsAfterLoad = repository.requests;
    bloc.add(const UpdateVisibleIndecies([2501]));
    await settle(tester);
    expect(repository.requests, requestsAfterLoad);

    // גלילה אל קצה הטעון טוענת את ההמשך.
    final lastLoaded = content.lastIndexWhere((line) => line.isNotEmpty);
    bloc.add(UpdateVisibleIndecies([lastLoaded]));
    await settle(tester);
    content = (bloc.state as TextBookLoaded).content;
    expect(content[lastLoaded + 1], _heavyImageLine);
  });
}
