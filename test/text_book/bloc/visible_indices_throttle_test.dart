import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// הגבלת קצב לעדכוני `visibleIndices` — במצב רציף בלבד.
///
/// במצב רציף כל פריים גלילה בתוך פסקה ממוזגת משנה את השורה הגלויה וגורר
/// rebuild של הפסקה כולה. הבדיקה הקריטית: הדילוג בטוח והמיקום הסופי מגיע.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('shouldDispatchVisibleIndicesNow — הכרעה טהורה', () {
    const interval = Duration(milliseconds: 100);

    test('שידור ראשון (אין מועד קודם) — תמיד עובר', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: null,
          throttleInterval: interval,
        ),
        isTrue,
      );
    });

    test('מיד אחרי שידור קודם — נחסם', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: Duration.zero,
          throttleInterval: interval,
        ),
        isFalse,
      );
    });

    test('מעט לפני תום החלון — נחסם', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: const Duration(milliseconds: 99),
          throttleInterval: interval,
        ),
        isFalse,
      );
    });

    test('בדיוק בתום החלון — עובר', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: interval,
          throttleInterval: interval,
        ),
        isTrue,
      );
    });

    test('אחרי תום החלון — עובר', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: const Duration(milliseconds: 250),
          throttleInterval: interval,
        ),
        isTrue,
      );
    });

    test('חלון אפס — לעולם לא חוסם', () {
      for (final elapsed in [
        Duration.zero,
        const Duration(milliseconds: 1),
        const Duration(seconds: 1),
      ]) {
        expect(
          TextBookBloc.shouldDispatchVisibleIndicesNow(
            sinceLastDispatch: elapsed,
            throttleInterval: Duration.zero,
          ),
          isTrue,
          reason: 'elapsed=$elapsed',
        );
      }
    });

    test('חלון ארוך חוסם גם השהיה בינונית', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: const Duration(milliseconds: 500),
          throttleInterval: const Duration(seconds: 1),
        ),
        isFalse,
      );
    });

    test('משך שלילי (שעון שהוזז אחורה) — עובר ולא נתקע', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: const Duration(milliseconds: -1),
          throttleInterval: interval,
        ),
        isTrue,
      );
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: const Duration(hours: -1),
          throttleInterval: interval,
        ),
        isTrue,
      );
    });

    test('ברירת המחדל של החלון פעילה גם בלי פרמטר מפורש', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: Duration.zero,
        ),
        isFalse,
      );
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });

    test('גלילה רגילה אינה נחסמת', () {
      expect(
        TextBookBloc.shouldDispatchVisibleIndicesNow(
          sinceLastDispatch: Duration.zero,
          continuousReadingMode: false,
          throttleInterval: interval,
        ),
        isTrue,
      );
    });
  });

  test('מיקום שפורסם לפני סיום הטעינה משודר אחריה', () async {
    final positionsListener = ValueNotifier<ReadingPosition?>(null);
    _pushSingleVisibleSegment(positionsListener, index: 30);
    final bloc = await _loadedBloc(positionsListener);
    await _waitFor(
      () {
        final state = bloc.state;
        return state is TextBookLoaded && state.visibleIndices.first == 30;
      },
      timeout: const Duration(milliseconds: 500),
      description: 'visibleIndices מתעדכן למיקום שפורסם מראש',
    );
    await bloc.close();
  });

  group('התנהגות ה-bloc בגלילה', () {
    test('רצף מהיר של אירועי גלילה רגילה משדר כל שינוי', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      final emittedVisibleIndices = <List<int>>[];
      final subscription = bloc.stream.listen((state) {
        if (state is TextBookLoaded) {
          emittedVisibleIndices.add(state.visibleIndices);
        }
      });

      for (var i = 0; i < 30; i++) {
        _pushSingleVisibleSegment(positionsListener, index: 5 + i % 20);
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
      await subscription.cancel();

      expect(
        emittedVisibleIndices.length,
        30,
        reason: 'גלילה רגילה אינה כפופה להגבלת הקצב',
      );
      expect(
        emittedVisibleIndices,
        isNotEmpty,
        reason: 'חייב להיות לפחות שידור אחד — אחרת המסך קופא',
      );

      await bloc.close();
    });

    test('המיקום הסופי תמיד מגיע גם כשהשידור המיידי דולג', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      // שני אירועים צמודים: השני נופל בתוך חלון החסימה ולכן ידולג
      // מיידית — הטיימר הנגרר חייב לשדר אותו.
      _pushSingleVisibleSegment(positionsListener, index: 12);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      _pushSingleVisibleSegment(positionsListener, index: 20);

      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded &&
              state.visibleIndices.isNotEmpty &&
              state.visibleIndices.first == 20;
        },
        description: 'visibleIndices מתעדכנות למיקום הסופי (20)',
      );

      await bloc.close();
    });

    test('אירוע הגלילה הראשון משודר מיד, בלי השהיה', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      _pushSingleVisibleSegment(positionsListener, index: 25);

      // ללא המתנה לטיימר הנגרר: הראשון עובר כי אין מועד שידור קודם.
      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded &&
              state.visibleIndices.isNotEmpty &&
              state.visibleIndices.first == 25;
        },
        timeout: const Duration(milliseconds: 120),
        description: 'שידור מיידי של אירוע הגלילה הראשון',
      );

      await bloc.close();
    });

    test('גלילה רגילה מעדכנת גם בתוך חלון ההגבלה', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      _pushSingleVisibleSegment(positionsListener, index: 12);
      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded && state.visibleIndices.first == 12;
        },
        description: 'המיקום הראשון (12) משודר',
      );

      _pushSingleVisibleSegment(positionsListener, index: 20);
      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded && state.visibleIndices.first == 20;
        },
        timeout: const Duration(milliseconds: 120),
        description: 'המיקום השני (20) משודר מיידית במצב רגיל',
      );

      await bloc.close();
    });

    test('גלילה איטית מהחלון לא נחסמת כלל', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      for (final index in [11, 17, 23]) {
        _pushSingleVisibleSegment(positionsListener, index: index);
        await _waitFor(
          () {
            final state = bloc.state;
            return state is TextBookLoaded &&
                state.visibleIndices.isNotEmpty &&
                state.visibleIndices.first == index;
          },
          description: 'visibleIndices = $index',
        );
        // מעבר לחלון ההגבלה בין הצעדים.
        await Future<void>.delayed(const Duration(milliseconds: 130));
      }

      await bloc.close();
    });

    test('currentTitle עוקב אחרי הגלילה גם עם הגבלת הקצב', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      // גלילה אחורה בכמה אירועים צמודים. כל האינדקסים בטווח "סעיף א"
      // (שורות 5–9), כך שמצב הסיום דטרמיניסטי ולא תלוי באיזה אירוע שודר.
      for (final index in [9, 8, 7, 6]) {
        _pushSingleVisibleSegment(positionsListener, index: index);
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }

      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded &&
              state.currentTitle == 'סעיף א' &&
              state.visibleIndices.isNotEmpty &&
              state.visibleIndices.first == 6;
        },
        description: 'currentTitle="סעיף א" ו-visibleIndices=[6] אחרי גלילה',
      );

      await bloc.close();
    });

    test('כל פרץ גלילה רגילה משדר את כל האירועים', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      final seen = <int>[];
      final subscription = bloc.stream.listen((state) {
        if (state is TextBookLoaded && state.visibleIndices.isNotEmpty) {
          seen.add(state.visibleIndices.first);
        }
      });

      const bursts = [
        [5, 6, 7],
        [15, 16, 17],
        [25, 26, 27],
      ];
      for (final burst in bursts) {
        for (final index in burst) {
          _pushSingleVisibleSegment(positionsListener, index: index);
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      await subscription.cancel();

      for (final burst in bursts) {
        expect(
          seen,
          contains(burst.last),
          reason: 'סוף הפרץ ${burst.first}..${burst.last} חייב להישדר',
        );
      }
      expect(seen.last, 27, reason: 'המיקום הסופי חייב להגיע');
      expect(
        seen.length,
        bursts.expand((b) => b).length,
        reason: 'גלילה רגילה אינה כפופה להגבלת הקצב',
      );

      await bloc.close();
    });

    test('אירוע בודד משודר ולא נבלע בחסימה', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      _pushSingleVisibleSegment(positionsListener, index: 8);
      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded &&
              state.visibleIndices.isNotEmpty &&
              state.visibleIndices.first == 8;
        },
        description: 'אירוע בודד משודר',
      );

      await bloc.close();
    });

    test('חזרה למיקום המקורי בתוך פרץ לא משאירה state שגוי', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      _pushSingleVisibleSegment(positionsListener, index: 10);
      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded &&
              state.visibleIndices.isNotEmpty &&
              state.visibleIndices.first == 10;
        },
        description: 'מיקום התחלתי',
      );

      // הלוך ושוב מהיר שמסתיים בדיוק בנקודת המוצא.
      for (final index in [11, 12, 13, 12, 11, 10]) {
        _pushSingleVisibleSegment(positionsListener, index: index);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final state = bloc.state as TextBookLoaded;
      expect(state.visibleIndices.first, 10);

      await bloc.close();
    });

    test('גלילה ארוכה מסתיימת במיקום הנכון', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      for (var index = 2; index <= 30; index++) {
        _pushSingleVisibleSegment(positionsListener, index: index);
        await Future<void>.delayed(const Duration(milliseconds: 6));
      }

      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded &&
              state.visibleIndices.isNotEmpty &&
              state.visibleIndices.first == 30;
        },
        description: 'המיקום האחרון (30) הוא זה שנשאר ב-state',
      );

      await bloc.close();
    });

    test('סגירת ה-bloc בזמן חסימה לא מפילה את הטיימר הנגרר', () async {
      final positionsListener = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(positionsListener);

      _pushSingleVisibleSegment(positionsListener, index: 14);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      _pushSingleVisibleSegment(positionsListener, index: 19);

      await bloc.close();
      // הטיימר הנגרר יורה אחרי הסגירה — אסור שייזרק חריג.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });
}

/// מיקום נמדד ששורתו העליונה היא [index].
void _pushSingleVisibleSegment(
  ValueNotifier<ReadingPosition?> listener, {
  required int index,
}) {
  listener.value = ReadingPosition(topLine: index, visibleLines: [index]);
}

Future<TextBookBloc> _loadedBloc(
  ValueNotifier<ReadingPosition?> positionsListener,
) async {
  final bloc = TextBookBloc(
    repository: _TwoSectionRepository(),
    initialState: TextBookInitial.named(
      TextBook(title: 'ספר בדיקה'),
      10,
      false,
      const [],
      searchMode: SearchMode.exact,
      showPageShapeView: false,
    ),
    readingPosition: positionsListener,
  );

  bloc.add(
    const LoadContent(
      fontSize: 20,
      showSplitView: false,
      removeNikud: false,
      loadCommentators: false,
    ),
  );

  await _waitFor(
    () => bloc.state is TextBookLoaded,
    description: 'מצב טעון',
  );
  return bloc;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$description not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Repository עם TOC של שני סעיפים: "סעיף א" משורה 5, "סעיף ב" משורה 10.
class _TwoSectionRepository extends TextBookRepository {
  _TwoSectionRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async {
    return List.generate(40, (i) => 'שורה $i').join('\n');
  }

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final lines = List.generate(40, (i) => 'שורה $i');
    final ns = startLine.clamp(0, lines.length - 1);
    final ne = endLine.clamp(ns, lines.length - 1);
    return BookContentRange(
      startLine: ns,
      endLine: ne,
      totalLines: lines.length,
      lines: lines.sublist(ns, ne + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    return [
      TocEntry(text: 'סעיף א', index: 5, level: 1),
      TocEntry(text: 'סעיף ב', index: 10, level: 1),
    ];
  }

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
