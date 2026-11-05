import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  group('שער ההשהיה של האינדוקס', () {
    test('ללא השהיה — השער חוזר מיד', () async {
      final provider = _PauseProbeProvider()..isIndexing.value = true;
      final repository = IndexingRepository(provider);

      await repository.waitWhilePausedForTesting().timeout(
        const Duration(seconds: 1),
      );
    });

    test('השהיה חוסמת עד resumeIndexing', () async {
      final provider = _PauseProbeProvider()..isIndexing.value = true;
      final repository = IndexingRepository(provider)..pauseIndexing();

      var released = false;
      final gate = repository.waitWhilePausedForTesting().then(
        (_) => released = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(released, isFalse);
      expect(repository.isPaused, isTrue);

      repository.resumeIndexing();
      await gate.timeout(const Duration(seconds: 1));
      expect(repository.isPaused, isFalse);
    });

    test(
      'ביטול בזמן השהיה מעיר את השער כדי שהלולאה תפגוש את דגל הביטול',
      () async {
        final provider = _PauseProbeProvider()..isIndexing.value = true;
        final repository = IndexingRepository(provider)..pauseIndexing();

        final gate = repository.waitWhilePausedForTesting();
        repository.cancelIndexing();

        await gate.timeout(const Duration(seconds: 1));
        expect(provider.isIndexing.value, isFalse);
      },
    );

    test('ביטול ממאגר אחר מעיר השהיה ומשחרר את המאזין', () async {
      final provider = _PauseProbeProvider()..isIndexing.value = true;
      final repository = IndexingRepository(provider)..pauseIndexing();
      addTearDown(repository.resumeIndexing);
      final gate = repository.waitWhilePausedForTesting();

      IndexingRepository(provider).cancelIndexing();
      await gate.timeout(const Duration(seconds: 1));

      expect(repository.isPaused, isFalse);
      expect(provider.isIndexing.hasActiveListeners, isFalse);
    });

    test('השהיה חוזרת אחרי המשך חוסמת שוב', () async {
      final provider = _PauseProbeProvider()..isIndexing.value = true;
      final repository = IndexingRepository(provider)..pauseIndexing();
      repository.resumeIndexing();
      repository.pauseIndexing();

      var released = false;
      final gate = repository.waitWhilePausedForTesting().then(
        (_) => released = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(released, isFalse);

      repository.resumeIndexing();
      await gate.timeout(const Duration(seconds: 1));
      expect(provider.isIndexing.hasActiveListeners, isFalse);
    });
  });

  group('מצב אינדוקס חסכוני', () {
    test('מעביר את הדגל למנוע ושומר אותו לריצות הבאות', () async {
      final provider = _PauseProbeProvider();
      final repository = IndexingRepository(provider);
      expect(repository.isEconomyIndexing, isFalse);

      await repository.setEconomyIndexing(true);
      expect(repository.isEconomyIndexing, isTrue);
      expect(provider.engineInstance.economyCalls, [true]);

      await repository.setEconomyIndexing(false);
      expect(repository.isEconomyIndexing, isFalse);
      expect(provider.engineInstance.economyCalls, [true, false]);
    });

    test('כשל במנוע אינו משנה את המצב שנשמר', () async {
      final provider = _PauseProbeProvider()
        ..engineInstance.economyError = StateError('engine failed');
      final repository = IndexingRepository(provider);

      await expectLater(
        repository.setEconomyIndexing(true),
        throwsStateError,
      );

      expect(repository.isEconomyIndexing, isFalse);
    });
  });
}

class _PauseProbeProvider implements TantivyDataProvider {
  final engineInstance = _EconomyRecordingEngine();
  bool _economy = false;

  @override
  bool get isEconomyIndexing => _economy;

  @override
  Future<void> setEconomyIndexing(bool enabled) async {
    await engineInstance.setEconomyIndexing(enabled: enabled);
    _economy = enabled;
  }

  @override
  final _PauseFlag isIndexing = _PauseFlag();

  @override
  Future<SearchEngine> get engine async => engineInstance;

  @override
  set engine(Future<SearchEngine> value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

class _PauseFlag extends ValueNotifier<bool> {
  _PauseFlag() : super(false);

  bool get hasActiveListeners => hasListeners;
}

class _EconomyRecordingEngine implements SearchEngine {
  final economyCalls = <bool>[];
  Object? economyError;

  @override
  Future<void> setEconomyIndexing({required bool enabled}) async {
    economyCalls.add(enabled);
    final error = economyError;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}
