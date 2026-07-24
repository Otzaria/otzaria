import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/reader_location_tracker.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

@GenerateMocks([TabsBloc])
import 'reader_location_tracker_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  group('ReaderLocationTracker', () {
    late MockTabsBloc mockTabsBloc;
    late StreamController<TabsState> tabsStateController;
    late List<_DispatchedEvent> dispatchedEvents;

    setUp(() {
      mockTabsBloc = MockTabsBloc();
      tabsStateController = StreamController<TabsState>.broadcast();
      dispatchedEvents = [];

      when(mockTabsBloc.stream).thenAnswer((_) => tabsStateController.stream);
      when(mockTabsBloc.state).thenReturn(TabsState.initial());
    });

    tearDown(() {
      tabsStateController.close();
    });

    ReaderLocationTracker buildTracker({
      required TabsState initialState,
      ReaderLocationResolver? resolveLocation,
      Duration debounceDuration = Duration.zero,
    }) {
      when(mockTabsBloc.state).thenReturn(initialState);
      return ReaderLocationTracker(
        tabsBloc: mockTabsBloc,
        resolveLocation: resolveLocation ?? resolveReaderLocation,
        debounceDuration: debounceDuration,
        dispatchEvent: (topic, payload) async {
          dispatchedEvents.add(
            _DispatchedEvent(
              topic: topic,
              payload: Map<String, dynamic>.from(payload),
            ),
          );
        },
      );
    }

    void setCurrentState(TabsState state) {
      when(mockTabsBloc.state).thenReturn(state);
    }

    Future<void> settle() async {
      await Future.delayed(const Duration(milliseconds: 20));
    }

    test('initializes without errors', () {
      expect(
        () => ReaderLocationTracker(tabsBloc: mockTabsBloc),
        returnsNormally,
      );
    });

    test('disposes without errors', () {
      final tracker = ReaderLocationTracker(tabsBloc: mockTabsBloc);
      expect(() => tracker.dispose(), returnsNormally);
    });

    test('listens to TabsBloc stream on initialization', () async {
      final tracker = ReaderLocationTracker(tabsBloc: mockTabsBloc);

      // Verify that stream is being listened to
      verify(mockTabsBloc.stream).called(1);

      tracker.dispose();
    });

    test(
      'dispatches reader.current_ref_changed with correct payload for text tab',
      () async {
        final textTab = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 42,
        )..currentTitle.value = 'פרק ג';

        final tracker = buildTracker(
          initialState: TabsState(tabs: [textTab], currentTabIndex: 0),
        );
        await settle();

        expect(dispatchedEvents, hasLength(1));
        expect(dispatchedEvents.single.topic, 'reader.current_ref_changed');
        expect(dispatchedEvents.single.payload, {
          'currentBook': 'בראשית',
          'currentBookId': 'בראשית',
          'currentIndex': 42,
          'currentRef': 'פרק ג',
        });

        tracker.dispose();
      },
    );

    test(
      'dispatches reader.current_ref_changed with correct payload for pdf tab',
      () async {
        final pdfTab = PdfBookTab(
          book: PdfBook(title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
          pageNumber: 17,
        )..currentTitle.value = 'פרק ב';

        final tracker = buildTracker(
          initialState: TabsState(tabs: [pdfTab], currentTabIndex: 0),
        );
        await settle();

        expect(dispatchedEvents, hasLength(1));
        expect(dispatchedEvents.single.topic, 'reader.current_ref_changed');
        expect(dispatchedEvents.single.payload, {
          'currentBook': 'מסילת ישרים',
          'currentBookId': 'מסילת ישרים',
          'currentIndex': 17,
          'currentRef': 'פרק ב',
        });

        tracker.dispose();
      },
    );

    test(
      'dedupes identical snapshot when same location is emitted again',
      () async {
        final textTab = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 42,
        )..currentTitle.value = 'פרק ג';

        final tracker = buildTracker(
          initialState: TabsState(tabs: [textTab], currentTabIndex: 0),
        );
        await settle();

        textTab.bloc.emit(
          TextBookLoaded.initial(
            book: textTab.book,
            index: textTab.index,
            showLeftPane: false,
            splitView: false,
          ).copyWith(
            visibleIndices: [42],
            currentTitle: 'פרק ג',
          ),
        );
        await settle();

        expect(dispatchedEvents, hasLength(1));
        tracker.dispose();
      },
    );

    test(
      'dispatches again after active tab becomes null and returns',
      () async {
        final textTab = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 42,
        )..currentTitle.value = 'פרק ג';

        final tracker = buildTracker(
          initialState: TabsState(tabs: [textTab], currentTabIndex: 0),
        );
        await settle();

        setCurrentState(TabsState.initial());
        tabsStateController.add(TabsState.initial());
        await settle();

        final reopenedState = TabsState(tabs: [textTab], currentTabIndex: 0);
        setCurrentState(reopenedState);
        tabsStateController.add(reopenedState);
        await settle();

        expect(dispatchedEvents, hasLength(2));
        expect(dispatchedEvents.first.payload, dispatchedEvents.last.payload);

        tracker.dispose();
      },
    );

    test('ignores stale async snapshot after rapid tab switch', () async {
      final textTab1 = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 42,
      )..currentTitle.value = 'פרק ג';

      final textTab2 = TextBookTab(
        book: TextBook(title: 'שמות'),
        index: 10,
      )..currentTitle.value = 'פרק א';

      final pendingSnapshot = Completer<ReaderLocationSnapshot?>();
      final tracker = buildTracker(
        initialState: TabsState(tabs: [textTab1], currentTabIndex: 0),
        resolveLocation: (currentTab) {
          if (identical(currentTab, textTab1)) {
            return pendingSnapshot.future;
          }
          if (identical(currentTab, textTab2)) {
            return Future.value(
              const ReaderLocationSnapshot(
                currentBook: 'שמות',
                currentBookId: 'שמות',
                currentIndex: 10,
                currentRef: 'פרק א',
              ),
            );
          }
          return Future.value(null);
        },
      );
      await settle();

      final switchedState = TabsState(
        tabs: [textTab1, textTab2],
        currentTabIndex: 1,
      );
      setCurrentState(switchedState);
      tabsStateController.add(switchedState);
      await settle();

      pendingSnapshot.complete(
        const ReaderLocationSnapshot(
          currentBook: 'בראשית',
          currentBookId: 'בראשית',
          currentIndex: 42,
          currentRef: 'פרק ג',
        ),
      );
      await settle();

      expect(dispatchedEvents, hasLength(1));
      expect(dispatchedEvents.single.payload['currentBook'], 'שמות');
      tracker.dispose();
    });

    test('dispatches updated payload when title changes', () async {
      final textTab = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 42,
      )..currentTitle.value = 'פרק ג';

      final tracker = buildTracker(
        initialState: TabsState(tabs: [textTab], currentTabIndex: 0),
      );
      await settle();

      textTab.currentTitle.value = 'פרק ד';
      await settle();

      expect(dispatchedEvents, hasLength(2));
      expect(dispatchedEvents.last.payload['currentRef'], 'פרק ד');
      tracker.dispose();
    });

    test('resolves null snapshot for null tab', () async {
      final snapshot = await resolveReaderLocation(null);
      expect(snapshot, isNull);
    });
  });
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
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

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

class _DispatchedEvent {
  final String topic;
  final Map<String, dynamic> payload;

  const _DispatchedEvent({
    required this.topic,
    required this.payload,
  });
}
