import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';

/// `otzaria://open/book/<id>?index=<n>&select` must end in the state a click on
/// that paragraph gives, on a new tab and on a tab that is already open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  group('new tab', () {
    test('the line waits for the reader, then is selected', () async {
      final position = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(position, linkSelectedLine: 10);
      addTearDown(bloc.close);

      await _settle();
      expect(_loaded(bloc).selectedIndex, isNull);

      _show(position, [10, 11, 12]);
      await _waitFor(
        () => _loaded(bloc).selectedIndex == 10,
        description: 'line selected',
      );
      expect(_loaded(bloc).selectedIndices, {10});
    });

    test('a position published before the load is used by the load', () async {
      final position = ValueNotifier<ReadingPosition?>(
        ReadingPosition.target(10),
      );
      final bloc = await _loadedBloc(position, linkSelectedLine: 10);
      addTearDown(bloc.close);

      await _waitFor(
        () => _loaded(bloc).selectedIndex == 10,
        description: 'line selected',
      );
    });

    test('the tab hands its line to the bloc it creates', () async {
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 7,
        linkSelectedLine: 7,
      );
      addTearDown(tab.dispose);

      expect(tab.bloc.pendingLinkSelectionForTesting, 7);
    });
  });

  group('open tab', () {
    test('a far line is selected only when the reader reaches it', () async {
      final position = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(position);
      addTearDown(bloc.close);
      _show(position, [10, 11, 12]);

      bloc.add(const SelectLineWhenVisible(30));
      await _settle();
      expect(_loaded(bloc).selectedIndex, isNull);

      _show(position, [20, 21, 22]);
      await _settle();
      expect(_loaded(bloc).selectedIndex, isNull);

      _show(position, [30, 31, 32]);
      await _waitFor(
        () => _loaded(bloc).selectedIndex == 30,
        description: 'line selected',
      );
    });

    test('a line already on screen is selected at once', () async {
      final position = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(position);
      addTearDown(bloc.close);
      _show(position, [10, 11, 12]);

      bloc.add(const SelectLineWhenVisible(11));

      await _waitFor(
        () => _loaded(bloc).selectedIndex == 11,
        description: 'line selected',
      );
    });

    test('the selection survives the landing of the navigation', () async {
      final position = ValueNotifier<ReadingPosition?>(null);
      final bloc = await _loadedBloc(position);
      addTearDown(bloc.close);
      _show(position, [10, 11, 12]);

      // scrollToLine publishes the target first and measures after landing.
      position.value = ReadingPosition.target(30);
      bloc.add(const SelectLineWhenVisible(30));
      await _waitFor(
        () => _loaded(bloc).selectedIndex == 30,
        description: 'line selected',
      );

      _show(position, [30, 31, 32]);
      await _waitFor(
        () => _loaded(bloc).visibleIndices.contains(32),
        description: 'visible window updated',
      );
      expect(_loaded(bloc).selectedIndex, 30);
    });
  });

  test('a link and a click end in the same state', () async {
    final linkPosition = ValueNotifier<ReadingPosition?>(null);
    final link = await _loadedBloc(linkPosition, linkSelectedLine: 10);
    addTearDown(link.close);
    _show(linkPosition, [10, 11, 12]);

    final clickPosition = ValueNotifier<ReadingPosition?>(null);
    final click = await _loadedBloc(clickPosition);
    addTearDown(click.close);
    _show(clickPosition, [10, 11, 12]);
    await _waitFor(
      () => _loaded(click).visibleIndices.contains(12),
      description: 'visible window updated',
    );
    click.add(const UpdateSelectedIndex(10));

    await _waitFor(
      () =>
          _loaded(link).selectedIndex == 10 &&
          _loaded(click).selectedIndex == 10 &&
          _loaded(link).visibleIndices.contains(12),
      description: 'both selected',
    );
    await _settle();

    expect(_loaded(link).selectedIndices, _loaded(click).selectedIndices);
    expect(_loaded(link).visibleIndices, _loaded(click).visibleIndices);
    expect(_linkRefs(link), _linkRefs(click));
  });

  test('a click during the wait replaces the link selection', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);
    _show(position, [10, 11, 12]);

    bloc.add(const SelectLineWhenVisible(30));
    bloc.add(const UpdateSelectedIndex(11));
    await _waitFor(
      () => _loaded(bloc).selectedIndex == 11,
      description: 'click applied',
    );

    _show(position, [12, 13, 14]);
    await _settle();
    _show(position, [30, 31, 32]);
    await _settle();

    expect(_loaded(bloc).selectedIndex, isNot(30));
    expect(bloc.pendingLinkSelectionForTesting, isNull);
  });

  test('the selection is applied once', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position, linkSelectedLine: 10);
    addTearDown(bloc.close);

    _show(position, [10, 11, 12]);
    await _waitFor(
      () => _loaded(bloc).selectedIndex == 10,
      description: 'line selected',
    );

    bloc.add(const UpdateSelectedIndex(null));
    await _waitFor(
      () => _loaded(bloc).selectedIndex == null,
      description: 'selection cleared',
    );

    _show(position, [9, 10, 11]);
    await _settle();

    expect(_loaded(bloc).selectedIndex, isNull);
  });

  test('without the flag a load selects nothing', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);

    _show(position, [10, 11, 12]);
    await _settle();

    expect(_loaded(bloc).selectedIndex, isNull);
    expect(_loaded(bloc).selectedIndices, isEmpty);
  });
}

TextBookLoaded _loaded(TextBookBloc bloc) => bloc.state as TextBookLoaded;

List<String> _linkRefs(TextBookBloc bloc) =>
    _loaded(bloc).visibleLinks.map((link) => link.heRef).toList();

void _show(ValueNotifier<ReadingPosition?> position, List<int> lines) {
  position.value = ReadingPosition(topLine: lines.first, visibleLines: lines);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Future<TextBookBloc> _loadedBloc(
  ValueNotifier<ReadingPosition?> position, {
  int? linkSelectedLine,
}) async {
  final bloc = TextBookBloc(
    repository: _FortyLineRepository(),
    initialState: TextBookInitial.named(
      TextBook(title: 'ספר בדיקה'),
      10,
      false,
      const [],
      searchMode: SearchMode.exact,
      showPageShapeView: false,
    ),
    readingPosition: position,
    linkSelectedLine: linkSelectedLine,
  );

  bloc.add(
    const LoadContent(
      fontSize: 20,
      showSplitView: false,
      removeNikud: false,
      loadCommentators: false,
    ),
  );

  await _waitFor(() => bloc.state is TextBookLoaded, description: 'loaded');
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

class _FortyLineRepository extends TextBookRepository {
  _FortyLineRepository() : super(fileSystem: FileSystemData.instance);

  static final _lines = List.generate(40, (i) => 'שורה $i');

  @override
  Future<String> getBookContent(TextBook book) async => _lines.join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final start = startLine.clamp(0, _lines.length - 1);
    final end = endLine.clamp(start, _lines.length - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: _lines.length,
      lines: _lines.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => [
    TocEntry(text: 'סעיף א', index: 5, level: 1),
  ];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => [
    for (var i = startIndex; i <= endIndex; i++)
      Link(
        heRef: 'מקור $i',
        index1: i + 1,
        path2: 'ספר $i.txt',
        index2: 1,
        connectionType: 'reference',
      ),
  ];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, dynamic> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

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
  Set<dynamic> getKeys() => _values.keys.toSet();

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      _values[key] as T? ?? defaultValue;

  @override
  Future<void> init() async {}

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
