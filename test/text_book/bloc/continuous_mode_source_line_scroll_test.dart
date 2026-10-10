// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:flutter/animation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _RecordingScrollController extends ItemScrollController {
  final List<int> scrolledTo = [];

  @override
  bool get isAttached => true;

  @override
  Future<void> scrollTo({
    required int index,
    double alignment = 0,
    required Duration duration,
    Curve curve = Curves.linear,
    List<double> opacityAnimationWeights = const [40, 20, 40],
  }) async {
    scrolledTo.add(index);
  }
}

const _content = [
  '<h2>פרק א</h2>',
  'שורה 1',
  'שורה 2',
  'שורה 3',
  '<h2>פרק ב</h2>',
  'שורה 5',
  'שורה 6',
  'שורה 7',
  'שורה 8',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ReadingSegment> segments;
  late _RecordingScrollController scroll;
  late TextBookBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final book = TextBook(title: 'בראשית');
    segments = buildReadingSegments(_content, continuous: true);
    scroll = _RecordingScrollController();
    final positions = ItemPositionsListener.create();
    bloc = TextBookBloc(
      repository: TextBookRepository(fileSystem: FileSystemData.instance),
      initialState: TextBookInitial(book, 0, false, const []),
      scrollController: scroll,
      positionsListener: positions,
    );
    bloc.emit(
      TextBookLoaded(
        book: book,
        showLeftPane: false,
        content: _content,
        fontSize: 18,
        showSplitView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        visibleLinks: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        pinLeftPane: false,
        searchText: '',
        scrollController: scroll,
        positionsListener: positions,
        continuousReadingMode: true,
        supportsContinuousReadingMode: true,
        readingSegments: segments,
        selectedIndex: 7,
        showPageShapeView: true,
      ),
    );
    final contentApplied = bloc.stream.firstWhere(
      (state) => state is TextBookLoaded && state.contentVersion > 0,
    );
    bloc.add(ApplyFullBookContent(bookTitle: book.title, content: _content));
    await contentApplied;
  });

  tearDown(() => bloc.close());

  test(
    'ApplyMarkHighlight scrolls to the paragraph holding the line',
    () async {
      expect(segmentIndexForLine(segments, 7), 3);

      bloc.add(
        const ApplyMarkHighlight(permanentHighlightLine: 7, scrollToIndex: 7),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(scroll.scrolledTo, [3]);
    },
  );

  test(
    'leaving page shape scrolls to the paragraph of the selected line',
    () async {
      bloc.add(const TogglePageShapeView(false));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(scroll.scrolledTo, [3]);
    },
  );
  for (final continuous in [false, true]) {
    test('delayed page shape exit uses current mode: $continuous', () async {
      if (continuous) {
        final initial = bloc.state as TextBookLoaded;
        bloc.emit(
          initial.copyWith(
            continuousReadingMode: false,
            readingSegments: buildReadingSegments(_content, continuous: false),
          ),
        );
      }
      bloc.add(const TogglePageShapeView(false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      bloc.add(ToggleContinuousReadingMode(continuous));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final current = bloc.state as TextBookLoaded;
      expect(current.continuousReadingMode, continuous);
      expect(current.selectedIndex, 7);
      expect(scroll.scrolledTo, [continuous ? 3 : 7]);
    });
  }

  test('delayed page shape exit skips a closed bloc', () async {
    bloc.add(const TogglePageShapeView(false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await bloc.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(scroll.scrolledTo, isEmpty);
  });

  for (final change in ['page shape', 'tzurat hadaf', 'book']) {
    test('delayed page shape exit skips changed $change', () async {
      bloc.add(const TogglePageShapeView(false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final current = bloc.state as TextBookLoaded;
      switch (change) {
        case 'page shape':
          bloc.add(const TogglePageShapeView(true));
        case 'tzurat hadaf':
          bloc.add(const ToggleTzuratHadafView(true));
        case 'book':
          bloc.emit(current.copyWith(book: TextBook(title: 'שמות')));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(scroll.scrolledTo, isEmpty);
    });
  }
  test(
    'delayed page shape exit preserves the target after selection clears',
    () async {
      bloc.add(const TogglePageShapeView(false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      bloc.add(const UpdateVisibleIndecies([1]));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect((bloc.state as TextBookLoaded).selectedIndex, isNull);
      expect(scroll.scrolledTo, [3]);
    },
  );
}
