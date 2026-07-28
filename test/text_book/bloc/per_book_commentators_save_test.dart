import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

TextBookLoaded _seed(TextBook book, {List<String> active = const []}) {
  return TextBookLoaded(
    book: book,
    content: const ['שורה'],
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    activeCommentators: active,
    commentatorGroups: const [],
    availableCommentators: const ['רש"י', 'רמב"ן'],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDataRoot;
  late TextBook book;
  late TextBookBloc bloc;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    tempDataRoot = await Directory.systemTemp.createTemp('commentators_save_');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
    book = TextBook(title: 'ספר בדיקה');
    bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 0, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
  });

  tearDown(() async {
    await bloc.close();
    // חייב לקדום להסרת ה-override: השמירה יוצאת לדרך בלי await, ובלי
    // ההמתנה היא מחזיקה את הקובץ פתוח והמחיקה נכשלת ב-Windows.
    await PerBookSettings.settle();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDataRoot.exists()) {
      await tempDataRoot.delete(recursive: true);
    }
  });

  /// מזין מצב טעון ומחיל אירוע בחירת מפרשים, ואז ממתין לשמירה שיצאה לדרך.
  Future<void> select(
    List<String> commentators, {
    bool isUserAction = true,
    bool isRestore = false,
    TextBook? forBook,
  }) async {
    bloc.emit(_seed(forBook ?? book));
    bloc.add(
      UpdateCommentators(
        commentators,
        isUserAction: isUserAction,
        isRestore: isRestore,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await PerBookSettings.settle();
  }

  group('שמירת בחירת מפרשים פר-ספר', () {
    test('בחירה ידנית נשמרת ונטענת מהדיסק', () async {
      await select(const ['רש"י', 'רמב"ן']);

      final saved = await TextBookPerBookSettings.load(book);
      expect(saved?.activeCommentators, ['רש"י', 'רמב"ן']);
    });

    test('בחירה ריקה נשמרת — המשתמש ביטל את הכל', () async {
      await select(const ['רש"י']);
      await select(const []);

      final saved = await TextBookPerBookSettings.load(book);
      expect(saved?.activeCommentators, isEmpty);
    });

    test('בחירה אוטומטית (isUserAction:false) אינה נשמרת', () async {
      await select(const ['רש"י'], isUserAction: false);

      expect(await TextBookPerBookSettings.load(book), isNull);
    });

    test('שחזור בחירה שמורה אינו כותב מחדש', () async {
      await select(const ['רש"י'], isUserAction: false, isRestore: true);

      expect(await TextBookPerBookSettings.load(book), isNull);
    });

    test('ספר אישי אינו נשמר פר-ספר', () async {
      final userBook = TextBook(title: 'ספר אישי', isUserBook: true);
      await select(const ['רש"י'], forBook: userBook);

      expect(await TextBookPerBookSettings.load(userBook), isNull);
    });

    test('בחירות עוקבות — האחרונה מנצחת', () async {
      await select(const ['רש"י']);
      await select(const ['רמב"ן']);

      final saved = await TextBookPerBookSettings.load(book);
      expect(saved?.activeCommentators, ['רמב"ן']);
    });

    test('השמירה אינה דורסת הגדרות תצוגה קיימות של אותו ספר', () async {
      await TextBookPerBookSettings.mutate(
        book,
        (existing) =>
            (existing ?? TextBookPerBookSettings()).copyWith(fontSize: 27),
      );

      await select(const ['רש"י']);

      final saved = await TextBookPerBookSettings.load(book);
      expect(saved?.fontSize, 27);
      expect(saved?.activeCommentators, ['רש"י']);
    });

    test('שני ספרים שונים נשמרים בנפרד', () async {
      final other = TextBook(title: 'ספר אחר');
      await select(const ['רש"י']);
      await select(const ['רמב"ן'], forBook: other);

      expect(
        (await TextBookPerBookSettings.load(book))?.activeCommentators,
        ['רש"י'],
      );
      expect(
        (await TextBookPerBookSettings.load(other))?.activeCommentators,
        ['רמב"ן'],
      );
    });
  });

  group('רגרסיה: השמירה התלויה מול מחיקת שורש הנתונים', () {
    test('סגירת ה-bloc לבדה אינה מבטיחה שהשמירה הסתיימה', () async {
      bloc.emit(_seed(book));
      bloc.add(const UpdateCommentators(['רש"י']));
      await Future<void>.delayed(Duration.zero);
      await bloc.close();

      // ההמתנה כאן היא מה שהופך את המחיקה לבטוחה — בלעדיה היא נכשלה
      // ב-Windows עם PathAccessException (errno 32).
      await PerBookSettings.settle();

      await expectLater(tempDataRoot.delete(recursive: true), completes);
      expect(await tempDataRoot.exists(), isFalse);
      await tempDataRoot.create(recursive: true);
    });

    test('כמה בחירות רצופות — ההמתנה מכסה את כל התור', () async {
      bloc.emit(_seed(book));
      for (final commentator in ['רש"י', 'רמב"ן', 'ספורנו']) {
        bloc.add(UpdateCommentators([commentator]));
      }
      await Future<void>.delayed(Duration.zero);

      await PerBookSettings.settle();

      final saved = await TextBookPerBookSettings.load(book);
      expect(saved?.activeCommentators, ['ספורנו']);
      await expectLater(tempDataRoot.delete(recursive: true), completes);
      await tempDataRoot.create(recursive: true);
    });
  });
}
