import 'dart:math';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

// ---------------------------------------------------------------------------
// Mocks / stubs
// ---------------------------------------------------------------------------

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _StubTabsBloc extends Mock implements TabsBloc {
  @override
  TabsState get state => TabsState.initial();
}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _StubCalendarCubit extends Mock implements CalendarCubit {}

class _StubPluginRegistryRepository extends PluginRegistryRepository {
  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(
          String pluginId) async =>
      [];

  @override
  Future<void> setPermission(
      String pluginId, String permission, bool granted) async {}
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

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

InstalledPlugin _buildPlugin() => InstalledPlugin(
      pluginId: 'test.plugin',
      name: 'Test Plugin',
      version: '1.0.0',
      installPath: '/',
      entrypointPath: 'index.html',
      enabled: true,
      pinned: true,
      manifest: PluginManifest(
        schemaVersion: 1,
        id: 'test.plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const ['reader.highlight'],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Test Plugin',
        toolTabOrder: 1,
        defaultPinned: true,
        publishedDataTypes: const [],
      ),
      installedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

PluginBridgeAdapter _makeAdapter() {
  final deps = PluginBridgeDependencies(
    historyBloc: _MockHistoryBloc(),
    tabsBloc: _StubTabsBloc(),
    navigationBloc: _MockNavigationBloc(),
    calendarCubit: _StubCalendarCubit(),
    workspaceBloc: _MockWorkspaceBloc(),
    searchRepository: _MockSearchRepository(),
    personalNotesRepository: _MockPersonalNotesRepository(),
    bookOpenCoordinator: _MockBookOpenCoordinator(),
    themePayloadBuilder: () => <String, dynamic>{},
    showConfirmDialog: ({required title, required content}) async => true,
    showWarningDialog:
        ({required title, required content, required subtitle}) async => true,
  );
  return PluginBridgeAdapter(
    _buildPlugin(),
    dependencies: deps,
    pluginRepository: _StubPluginRegistryRepository(),
  );
}

// Convenience: call reader action
Future<dynamic> _reader(
    PluginBridgeAdapter a, String action, Map<String, dynamic> args) async {
  return a.execute('reader', action, args);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  // ── unit tests ────────────────────────────────────────────────────────────

  group('setHighlight — whole-line (backward compat)', () {
    test('saves and retrieves whole-line highlight without start/end',
        () async {
      final a = _makeAdapter();
      await _reader(a, 'setHighlight',
          {'bookId': 'בראשית', 'index': 5, 'color': '#FF0', 'label': 'x'});
      final list = await _reader(a, 'getHighlights', {'bookId': 'בראשית'})
          as List<dynamic>;
      expect(list.length, 1);
      expect(list.first['index'], 5);
      expect(list.first.containsKey('start'), isFalse);
      expect(list.first.containsKey('end'), isFalse);
    });
  });

  group('setHighlight — inline (start/end)', () {
    test('saves inline highlight with start and end', () async {
      final a = _makeAdapter();
      await _reader(a, 'setHighlight',
          {'bookId': 'שמות', 'index': 10, 'start': 20, 'end': 30});
      final list =
          await _reader(a, 'getHighlights', {'bookId': 'שמות'}) as List;
      expect(list.length, 1);
      expect(list.first['start'], 20);
      expect(list.first['end'], 30);
    });

    test('start == end is valid (single char highlight)', () async {
      final a = _makeAdapter();
      await expectLater(
        _reader(a, 'setHighlight',
            {'bookId': 'b', 'index': 1, 'start': 5, 'end': 5}),
        completes,
      );
    });

    test('rejects start without end', () async {
      final a = _makeAdapter();
      await expectLater(
        _reader(a, 'setHighlight', {'bookId': 'b', 'index': 1, 'start': 5}),
        throwsA(
            predicate((e) => e.toString().contains('error.invalid_params'))),
      );
    });

    test('rejects end without start', () async {
      final a = _makeAdapter();
      await expectLater(
        _reader(a, 'setHighlight', {'bookId': 'b', 'index': 1, 'end': 10}),
        throwsA(
            predicate((e) => e.toString().contains('error.invalid_params'))),
      );
    });

    test('rejects start > end', () async {
      final a = _makeAdapter();
      await expectLater(
        _reader(a, 'setHighlight',
            {'bookId': 'b', 'index': 1, 'start': 50, 'end': 10}),
        throwsA(
            predicate((e) => e.toString().contains('error.invalid_params'))),
      );
    });

    test('rejects negative start', () async {
      final a = _makeAdapter();
      await expectLater(
        _reader(a, 'setHighlight',
            {'bookId': 'b', 'index': 1, 'start': -1, 'end': 5}),
        throwsA(
            predicate((e) => e.toString().contains('error.invalid_params'))),
      );
    });
  });

  group('clearHighlight — broad (no start/end)', () {
    test('clears all highlights for given index', () async {
      final a = _makeAdapter();
      await _reader(
          a, 'setHighlight', {'bookId': 'b', 'index': 3, 'color': '#FF0'});
      await _reader(a, 'setHighlight',
          {'bookId': 'b', 'index': 3, 'start': 10, 'end': 20});
      await _reader(
          a, 'setHighlight', {'bookId': 'b', 'index': 5, 'color': '#00F'});
      // broad clear of index 3 should remove both highlights at index 3
      await _reader(a, 'clearHighlight', {'bookId': 'b', 'index': 3});
      final list = await _reader(a, 'getHighlights', {'bookId': 'b'}) as List;
      expect(list.length, 1); // only index 5 remains
      expect(list.first['index'], 5);
    });

    test('clearHighlight is idempotent for non-existing index', () async {
      final a = _makeAdapter();
      await expectLater(
        _reader(a, 'clearHighlight', {'bookId': 'b', 'index': 999}),
        completion(true),
      );
    });
  });

  group('clearHighlight — precise (with start/end)', () {
    test('removes only the matching inline highlight', () async {
      final a = _makeAdapter();
      await _reader(a, 'setHighlight',
          {'bookId': 'b', 'index': 7, 'start': 10, 'end': 20});
      await _reader(a, 'setHighlight',
          {'bookId': 'b', 'index': 7, 'start': 30, 'end': 40});
      // precise delete of 7:10:20 — the other one must survive
      await _reader(a, 'clearHighlight',
          {'bookId': 'b', 'index': 7, 'start': 10, 'end': 20});
      final list = await _reader(a, 'getHighlights', {'bookId': 'b'}) as List;
      expect(list.length, 1);
      expect(list.first['start'], 30);
      expect(list.first['end'], 40);
    });

    test('precise clear is idempotent for non-existing range', () async {
      final a = _makeAdapter();
      await _reader(a, 'setHighlight',
          {'bookId': 'b', 'index': 7, 'start': 10, 'end': 20});
      await _reader(a, 'clearHighlight',
          {'bookId': 'b', 'index': 7, 'start': 50, 'end': 60});
      final list = await _reader(a, 'getHighlights', {'bookId': 'b'}) as List;
      expect(list.length, 1); // original survives
    });
  });

  // ── Property-Based Tests ─────────────────────────────────────────────────

  group(
    'Feature: plugin-api-enhancements, Property 2: start ≤ end invariant',
    () {
      // **Validates: Requirements 1.5, 7.1, 7.2**
      //
      // For any (start, end) pair where start > end, setHighlight must reject.
      // For start <= end it must accept.
      test('start > end always rejected; start <= end always accepted',
          () async {
        final rng = Random(1);
        for (var i = 0; i < 200; i++) {
          final a = _makeAdapter();
          final base = rng.nextInt(500);
          final delta = rng.nextInt(200) + 1; // always >= 1

          // start > end → must reject
          await expectLater(
            _reader(a, 'setHighlight', {
              'bookId': 'b',
              'index': i,
              'start': base + delta,
              'end': base,
            }),
            throwsA(predicate(
                (e) => e.toString().contains('error.invalid_params'))),
            reason:
                'iteration $i: start=${base + delta} > end=$base should reject',
          );

          // start == end → must accept
          await expectLater(
            _reader(a, 'setHighlight',
                {'bookId': 'b', 'index': i, 'start': base, 'end': base}),
            completes,
            reason: 'iteration $i: start==end=$base should accept',
          );

          // start < end → must accept
          final a2 = _makeAdapter();
          await expectLater(
            _reader(a2, 'setHighlight', {
              'bookId': 'b',
              'index': i,
              'start': base,
              'end': base + delta,
            }),
            completes,
            reason:
                'iteration $i: start=$base < end=${base + delta} should accept',
          );
        }
      });
    },
  );

  group(
    'Feature: plugin-api-enhancements, Property 4: idempotence of clearHighlight',
    () {
      // **Validates: Requirements 1.10**
      //
      // Calling clearHighlight for a range that doesn't exist must not throw
      // and must return true (idempotent).
      test('clearHighlight is always idempotent', () async {
        final rng = Random(2);
        for (var i = 0; i < 200; i++) {
          final a = _makeAdapter();
          final idx = rng.nextInt(1000);
          // no highlight registered → clear should be silent and return true
          final r1 = await _reader(
              a, 'clearHighlight', {'bookId': 'book_$i', 'index': idx});
          expect(r1, isTrue,
              reason: 'iteration $i: first clear should return true');
          // second clear — still idempotent
          final r2 = await _reader(
              a, 'clearHighlight', {'bookId': 'book_$i', 'index': idx});
          expect(r2, isTrue,
              reason: 'iteration $i: second clear should return true');
        }
      });
    },
  );

  group(
    'Feature: plugin-api-enhancements, Property 5: precise delete leaves neighbors intact',
    () {
      // **Validates: Requirements 1.9**
      //
      // After adding N inline highlights to the same index,
      // deleting one of them must leave N-1 highlights intact.
      test('precise delete does not affect other highlights at same index',
          () async {
        final rng = Random(3);
        for (var i = 0; i < 100; i++) {
          final a = _makeAdapter();
          const n = 4;
          final index = rng.nextInt(100);
          // add n non-overlapping ranges
          final ranges = List.generate(n, (j) {
            final s = j * 100 + rng.nextInt(10);
            final e = s + 10 + rng.nextInt(40);
            return (s, e);
          });
          for (final (s, e) in ranges) {
            await _reader(a, 'setHighlight',
                {'bookId': 'b', 'index': index, 'start': s, 'end': e});
          }
          // delete the first range
          final (ds, de) = ranges.first;
          await _reader(a, 'clearHighlight',
              {'bookId': 'b', 'index': index, 'start': ds, 'end': de});
          final list =
              await _reader(a, 'getHighlights', {'bookId': 'b'}) as List;
          expect(list.length, n - 1,
              reason:
                  'iteration $i: expected ${n - 1} highlights after deleting one');
        }
      });
    },
  );

  group(
    'Feature: plugin-api-enhancements, Property 6: start without end (and vice versa) always rejected',
    () {
      // **Validates: Requirements 1.2, 1.3**
      test('start-only is always rejected', () async {
        final rng = Random(4);
        for (var i = 0; i < 100; i++) {
          final a = _makeAdapter();
          final s = rng.nextInt(500);
          await expectLater(
            _reader(a, 'setHighlight', {'bookId': 'b', 'index': i, 'start': s}),
            throwsA(predicate(
                (e) => e.toString().contains('error.invalid_params'))),
            reason: 'iteration $i: start-only should always reject',
          );
        }
      });

      test('end-only is always rejected', () async {
        final rng = Random(5);
        for (var i = 0; i < 100; i++) {
          final a = _makeAdapter();
          final e = rng.nextInt(500);
          await expectLater(
            _reader(a, 'setHighlight', {'bookId': 'b', 'index': i, 'end': e}),
            throwsA(predicate(
                (e2) => e2.toString().contains('error.invalid_params'))),
            reason: 'iteration $i: end-only should always reject',
          );
        }
      });
    },
  );
}
