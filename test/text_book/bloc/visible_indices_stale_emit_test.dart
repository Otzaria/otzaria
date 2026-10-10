import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// `UpdateVisibleIndecies` מצלם את ה-state בכניסה למטפל. כל `await` בדרך
/// ל-emit מאפשר לאירוע אחר לפלוט מצב חדש, וה-emit של הצילום המיושן דורס אותו —
/// כך חלונית הצד נשארה פתוחה בטלפון אחרי ניווט מעץ הניווט.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  test('סגירת חלונית הצד מיד אחרי עדכון הגלילה לא נדרסת', () async {
    final bloc = await _loadedBloc(showLeftPane: true);

    bloc.add(const UpdateVisibleIndecies([12, 13, 14]));
    bloc.add(const ToggleLeftPane(false));

    await _waitFor(
      () {
        final state = bloc.state;
        return state is TextBookLoaded && state.visibleIndices.first == 12;
      },
      description: 'visibleIndices התעדכנו ל-12',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = bloc.state as TextBookLoaded;
    expect(
      state.showLeftPane,
      isFalse,
      reason:
          'ToggleLeftPane נפלט אחרי הצילום — אסור שה-emit של הגלילה ידרוס אותו',
    );
    expect(state.visibleIndices, [12, 13, 14]);

    await bloc.close();
  });

  test('שינוי גודל הגופן מיד אחרי עדכון הגלילה לא נדרס', () async {
    final bloc = await _loadedBloc(showLeftPane: false);

    final before = (bloc.state as TextBookLoaded).fontSize;

    bloc.add(const UpdateVisibleIndecies([12, 13, 14]));
    bloc.add(UpdateFontSize(before + 8));

    await _waitFor(
      () {
        final state = bloc.state;
        return state is TextBookLoaded && state.visibleIndices.first == 12;
      },
      description: 'visibleIndices התעדכנו ל-12',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = bloc.state as TextBookLoaded;
    expect(
      state.fontSize,
      before + 8,
      reason:
          'UpdateFontSize נפלט אחרי הצילום — אסור שה-emit של הגלילה ידרוס אותו',
    );
    expect(state.visibleIndices, [12, 13, 14]);

    await bloc.close();
  });
}

Future<TextBookBloc> _loadedBloc({required bool showLeftPane}) async {
  final bloc = TextBookBloc(
    repository: _TwoSectionRepository(),
    initialState: TextBookInitial.named(
      TextBook(title: 'ספר בדיקה'),
      10,
      showLeftPane,
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
