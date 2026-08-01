import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// הגבלת קצב לעדכוני `visibleIndices`.
///
/// במצב קריאה רציף השורה הגלויה נגזרת משבר הגלילה בתוך פסקה ממוזגת, ולכן
/// משתנה כמעט בכל פריים. בלי הגבלה כל פריים גורר emit ו-rebuild של הפסקה
/// כולה. הבדיקה הקריטית כאן היא שהדילוג בטוח: המיקום הסופי חייב תמיד להגיע.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
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
  });

  group('התנהגות ה-bloc בגלילה', () {
    test('רצף מהיר של אירועי גלילה מצמצם את מספר ה-emit', () async {
      final positionsListener = ItemPositionsListener.create();
      final bloc = await _loadedBloc(positionsListener);

      final emittedVisibleIndices = <List<int>>[];
      final subscription = bloc.stream.listen((state) {
        if (state is TextBookLoaded) {
          emittedVisibleIndices.add(state.visibleIndices);
        }
      });

      // 30 אירועי גלילה בזה אחר זה, בקצב של פריימים (~8ms) — כמו גלילה
      // חלקה בתוך פסקה ממוזגת אחת.
      for (var i = 0; i < 30; i++) {
        _pushSingleVisibleSegment(positionsListener, index: 5 + i % 20);
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }

      // המתנה לטיימר הנגרר (160ms) + מרווח ל-emit האסינכרוני.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await subscription.cancel();

      expect(
        emittedVisibleIndices.length,
        lessThan(30),
        reason: 'הגבלת הקצב אמורה לחסוך emit-ים ביחס למספר אירועי הגלילה',
      );
      expect(
        emittedVisibleIndices,
        isNotEmpty,
        reason: 'חייב להיות לפחות שידור אחד — אחרת המסך קופא',
      );

      await bloc.close();
    });

    test('המיקום הסופי תמיד מגיע גם כשהשידור המיידי דולג', () async {
      final positionsListener = ItemPositionsListener.create();
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
      final positionsListener = ItemPositionsListener.create();
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

    test('גלילה איטית מהחלון לא נחסמת כלל', () async {
      final positionsListener = ItemPositionsListener.create();
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
      final positionsListener = ItemPositionsListener.create();
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

    test('סגירת ה-bloc בזמן חסימה לא מפילה את הטיימר הנגרר', () async {
      final positionsListener = ItemPositionsListener.create();
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

/// דוחף position יחיד שממלא את המסך — הצורה הפשוטה ביותר שעוברת את
/// `_filterBarelyVisiblePositions`.
void _pushSingleVisibleSegment(
  ItemPositionsListener listener, {
  required int index,
}) {
  (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value = [
    ItemPosition(index: index, itemLeadingEdge: 0, itemTrailingEdge: 0.95),
  ];
}

Future<TextBookBloc> _loadedBloc(
  ItemPositionsListener positionsListener,
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
    scrollController: ItemScrollController(),
    positionsListener: positionsListener,
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

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) return value;
    return defaultValue;
  }

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();
}
