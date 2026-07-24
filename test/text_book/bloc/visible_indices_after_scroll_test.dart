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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  group('currentTitle אחרי scroll עם alignment 0.05', () {
    test(
      'דחיפת positions עם שיירי הסעיף הקודם לא מזיזה את currentTitle אחורה',
      () async {
        // הסיטואציה: TOC עם שני סעיפים - "סעיף א" משורה 5 ו"סעיף ב" משורה 10.
        // המשתמש לחץ "סעיף ב" בניווט → scrollToSourceLine קרא ל-scrollTo(
        // index: 10, alignment: 0.05).
        //
        // ScrollablePositionedList אחרי הגלילה ידווח על שני items:
        //   * segment 9: itemLeadingEdge=-2, itemTrailingEdge=0.05
        //     (שיירי "סעיף א" שגלויים ב-5% העליונים של המסך)
        //   * segment 10: itemLeadingEdge=0.05, itemTrailingEdge=0.95
        //     ("סעיף ב" - היעד, תופס 90% מהמסך)
        //
        // ללא הסינון: refFromIndex(9) = "סעיף א" → currentTitle = "סעיף א".
        // עם הסינון: position 9 מסונן (visibility ratio 2.4% < 15%),
        //            visibleIndices = [10], currentTitle = "סעיף ב".

        final repository = _TwoSectionRepository();
        final positionsListener = ItemPositionsListener.create();
        final bloc = TextBookBloc(
          repository: repository,
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
          () {
            final state = bloc.state;
            return state is TextBookLoaded && state.currentTitle == 'סעיף ב';
          },
          description: 'מצב טעון עם currentTitle="סעיף ב"',
        );

        final initialState = bloc.state as TextBookLoaded;
        expect(initialState.visibleIndices, [10]);
        expect(initialState.currentTitle, 'סעיף ב');

        // מדמה את ScrollablePositionedList אחרי scrollTo(index: 10,
        // alignment: 0.05). הקסט ל-ValueNotifier הוא הדרך היחידה לדחוף ערך
        // לפי המבנה של החבילה.
        (positionsListener.itemPositions
                as ValueNotifier<Iterable<ItemPosition>>)
            .value = const [
          ItemPosition(
            index: 9,
            itemLeadingEdge: -2,
            itemTrailingEdge: 0.05,
          ),
          ItemPosition(
            index: 10,
            itemLeadingEdge: 0.05,
            itemTrailingEdge: 0.95,
          ),
        ];

        // אם המסנן עובד: אין emit חדש כי visibleIndices נשארות [10].
        // אם המסנן לא עובד: יתבצע emit עם currentTitle="סעיף א".
        // ממתינים זמן מספק לכל debounce ו-async refFromIndex להסתיים.
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final finalState = bloc.state as TextBookLoaded;
        expect(
          finalState.currentTitle,
          'סעיף ב',
          reason: 'הסעיף הקודם גלוי רק 5% - לא אמור לשנות את זיהוי המיקום',
        );
        expect(finalState.visibleIndices.first, 10);

        await bloc.close();
      },
    );

    test('גלילה אמיתית לתוך הסעיף הקודם כן מעדכנת את currentTitle', () async {
      // sanity check: כשהמשתמש באמת גולל אחורה (לא רק 5% עליונים), הזיהוי
      // צריך לעקוב. מדמים מצב שבו "סעיף א" תופס 60% מהמסך ו"סעיף ב" 35%.
      final repository = _TwoSectionRepository();
      final positionsListener = ItemPositionsListener.create();
      final bloc = TextBookBloc(
        repository: repository,
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
        () {
          final state = bloc.state;
          return state is TextBookLoaded && state.currentTitle == 'סעיף ב';
        },
        description: 'מצב טעון',
      );

      // 60% מהמסך עליון מציג segment 9 - גלילה ידנית אמיתית אחורה.
      (positionsListener.itemPositions as ValueNotifier<Iterable<ItemPosition>>)
          .value = const [
        ItemPosition(
          index: 9,
          itemLeadingEdge: 0,
          itemTrailingEdge: 0.6,
        ),
        ItemPosition(
          index: 10,
          itemLeadingEdge: 0.6,
          itemTrailingEdge: 0.95,
        ),
      ];

      await _waitFor(
        () {
          final state = bloc.state;
          return state is TextBookLoaded && state.currentTitle == 'סעיף א';
        },
        description: 'currentTitle="סעיף א" אחרי גלילה אחורה אמיתית',
      );

      await bloc.close();
    });
  });

  group('שחרור selectedIndex בגלילה רציפה', () {
    Future<TextBookBloc> loadedBloc() async {
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
        positionsListener: ItemPositionsListener.create(),
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

    // שולח אירוע גלילה אחד וממתין שהשורה העליונה תתעדכן.
    Future<void> scrollTo(TextBookBloc bloc, int first) async {
      bloc.add(
        UpdateVisibleIndecies(
          List.generate(5, (i) => first + i),
        ),
      );
      await _waitFor(
        () {
          final s = bloc.state as TextBookLoaded;
          return s.visibleIndices.isNotEmpty && s.visibleIndices.first == first;
        },
        description: 'visibleIndices.first == $first',
      );
    }

    test(
      'גלילה רציפה בצעדים קטנים מעבר ל-3 שורות מהקטע הנבחר מאפסת אותו',
      () async {
        final bloc = await loadedBloc();
        await scrollTo(bloc, 8); // הקטע 10 גלוי
        bloc.add(const UpdateSelectedIndex(10));
        await _waitFor(
          () => (bloc.state as TextBookLoaded).selectedIndex == 10,
          description: 'selectedIndex == 10',
        );

        // גלילה רציפה: כל אירוע מזיז את השורה העליונה בשורה אחת בלבד.
        // קודם הבאג נמדד event-to-event, אז delta תמיד 1 והבחירה לא השתחררה.
        for (final first in [9, 10, 11, 12, 13, 14]) {
          await scrollTo(bloc, first);
        }

        // first=14 → |10-14|=4 > 3, הבחירה משתחררת.
        expect((bloc.state as TextBookLoaded).selectedIndex, isNull);
        await bloc.close();
      },
    );

    test(
      'גלילה רציפה כלפי מעלה מעבר ל-3 שורות מהקטע הנבחר מאפסת אותו',
      () async {
        final bloc = await loadedBloc();
        await scrollTo(bloc, 10); // הקטע 10 בראש החלון
        bloc.add(const UpdateSelectedIndex(10));
        await _waitFor(
          () => (bloc.state as TextBookLoaded).selectedIndex == 10,
          description: 'selectedIndex == 10',
        );

        // גלילה כלפי מעלה: הקטע 10 יוצא מהקצה התחתון. המדידה מול הקצה הקרוב
        // מבטיחה התנהגות סימטרית — שחרור אחרי 3 שורות, כמו בגלילה כלפי מטה.
        for (final first in [9, 8, 7, 6, 5, 4, 3, 2]) {
          await scrollTo(bloc, first);
        }

        // last=6 → |10-6|=4 > 3, הבחירה משתחררת (ולא מיד עם השורה הראשונה).
        expect((bloc.state as TextBookLoaded).selectedIndex, isNull);
        await bloc.close();
      },
    );

    test('גלילה זעירה (עד 3 שורות מהקטע הנבחר) שומרת על הבחירה', () async {
      final bloc = await loadedBloc();
      await scrollTo(bloc, 8);
      bloc.add(const UpdateSelectedIndex(10));
      await _waitFor(
        () => (bloc.state as TextBookLoaded).selectedIndex == 10,
        description: 'selectedIndex == 10',
      );

      // 10 יצא מהתצוגה אך השורה העליונה במרחק 3 בלבד — בולעים קפיצת viewport.
      await scrollTo(bloc, 11); // first=11 → |10-11|=1
      await scrollTo(bloc, 13); // first=13 → |10-13|=3

      expect((bloc.state as TextBookLoaded).selectedIndex, 10);
      await bloc.close();
    });
  });
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

/// Repository עם TOC של שני סעיפים:
///   "סעיף א" משורה 5 (level 1)
///   "סעיף ב" משורה 10 (level 1)
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
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

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
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) return value;
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
