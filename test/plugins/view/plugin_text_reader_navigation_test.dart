import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/view/plugin_text_reader.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import '../services/plugin_text_reader_registry_test.dart' as fixture;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTabsBloc extends Mock implements TabsBloc {
  @override
  Stream<TabsState> get stream => const Stream.empty();
  @override
  TabsState get state => const TabsState(tabs: [], currentTabIndex: 0);
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));
  testWidgets(
    'search navigation after enabling embedded reader avoids detached offset controller',
    (tester) async {
      final controller = JumpAwareItemScrollController();
      var jumps = 0;
      controller.addBeforeJumpListener(() => jumps++);
      final offsets = ScrollOffsetController();
      final positions = ItemPositionsListener.create();
      await tester.pumpWidget(
        MaterialApp(
          home: ScrollablePositionedList.builder(
            itemScrollController: controller,
            scrollOffsetController: offsets,
            itemPositionsListener: positions,
            itemCount: 30,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(positions.itemPositions.value.any((p) => p.index == 2), isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final targets = <int>[];
      controller.externalScroll = (index, {int? sourceLineIndex}) async {
        targets.add(index);
      };
      await scrollToSourceLine(
        scrollController: controller,
        scrollOffsetController: offsets,
        positionsListener: positions,
        segments: buildReadingSegments(
          List.filled(30, 'טקסט'),
          continuous: false,
        ),
        lineIndex: 2,
        viewportExtent: 600,
        alignment: 0.35,
      );
      expect(targets, [2]);
      expect(jumps, 1);
      expect(controller.isNativeAttached, isFalse);
    },
  );
  testWidgets('embedded continuous reader receives requested source line', (
    tester,
  ) async {
    final book = TextBook(title: 'ברכות');
    final tab = TextBookTab(book: book, index: 0);
    final segments = buildReadingSegments([
      'שורה ראשונה',
      'שורה שנייה',
      'שורה שלישית',
    ], continuous: true);
    expect(segments, hasLength(1));
    tab.bloc.emit(
      TextBookLoaded.initial(
        book: book,
        index: 0,
        showLeftPane: false,
        splitView: false,
      ).copyWith(readingSegments: segments, continuousReadingMode: true),
    );
    await PluginTextReaderRegistry.instance.select(fixture.plugin(), false);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: _FakeTabsBloc()),
          BlocProvider<TextBookBloc>.value(value: tab.bloc),
        ],
        child: MaterialApp(
          home: PluginTextReader(tab: tab, nativeReader: const SizedBox()),
        ),
      ),
    );
    await PluginTextReaderRegistry.instance.select(fixture.plugin(), true);
    await scrollToSourceLine(
      scrollController: tab.scrollController,
      scrollOffsetController: null,
      positionsListener: null,
      segments: segments,
      lineIndex: 2,
      viewportExtent: 0,
    );
    expect(tab.index, 2);
    await PluginTextReaderRegistry.instance.select(fixture.plugin(), false);
    await tester.pumpWidget(const SizedBox());
    tab.dispose();
  });
  test('reader navigation payload carries currently active search', () {
    final book = TextBook(title: 'ברכות');
    final tab = TextBookTab(book: book, index: 0, searchText: 'החיפוש הקודם');
    tab.bloc.emit(
      TextBookLoaded.initial(
        book: book,
        index: 0,
        showLeftPane: false,
        splitView: false,
      ).copyWith(searchText: 'המילה החדשה'),
    );
    final payload = PluginTextReaderRegistry.bookPayload(tab);
    expect(payload['searchQuery'], 'המילה החדשה');
    tab.bloc.emit((tab.bloc.state as TextBookLoaded).copyWith(searchText: ''));
    expect(PluginTextReaderRegistry.bookPayload(tab)['searchQuery'], '');
    tab.dispose();
  });
}
