import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/find_ref_personal_books_setting.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

import '../helpers/memory_settings_cache.dart';

// ─── Fake repository ──────────────────────────────────────────────────────────
// implements (לא extends) — אין צורך ב-DataRepository, BLoC קורא רק findRefs

Future<List<DbReferenceResult>> _emptyFindRefs(String _) async => const [];

class _FakeRepository implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;

  final Future<List<DbReferenceResult>> Function(String) _fn;
  final Exception? _error;
  final List<bool> includePersonalBooksCalls = [];

  _FakeRepository({
    Future<List<DbReferenceResult>> Function(String)? fn,
    this._error,
  }) : _fn = fn ?? _emptyFindRefs;

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    includePersonalBooksCalls.add(includePersonalBooks);
    if (_error != null) throw _error;
    return _fn(ref);
  }

  @override
  void dispose() {}

  @override
  void cancelPendingSearch() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

DbReferenceResult _result({
  String title = 'בראשית',
  String ref = 'בראשית פרק א',
}) => DbReferenceResult(title: title, reference: ref, segment: 1);

FindRefBloc _bloc({
  Future<List<DbReferenceResult>> Function(String)? fn,
  Exception? error,
}) => FindRefBloc(
  findRefRepository: _FakeRepository(fn: fn, error: error),
);

// ─── Tests ────────────────────────────────────────────────────────────────────

// השהיה שמספיקה בנדיבות כדי לעבור את ה-debounce של 250ms בתוך ה-handler.
const _kPastDebounce = Duration(milliseconds: 400);

/// שני מחזורי debounce — למסלול שמריץ ניסיון חוזר אחרי ביטול זר.
const _kTwoDebounces = Duration(milliseconds: 900);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('FindRefBloc — כלול ספרים אישיים', () {
    for (final saved in [true, false]) {
      test(
        'בקשה בלי ערך מפורש (קישור/סיור) נוהגת לפי ההגדרה: $saved',
        () async {
          await FindRefPersonalBooksSetting.save(saved);
          final repository = _FakeRepository();
          final bloc = FindRefBloc(findRefRepository: repository);

          bloc.add(const SearchRefRequested('בראשית'));
          await Future<void>.delayed(_kPastDebounce);

          expect(repository.includePersonalBooksCalls, [saved]);
          await bloc.close();
        },
      );
    }

    test('ערך מפורש גובר על ההגדרה', () async {
      await FindRefPersonalBooksSetting.save(true);
      final repository = _FakeRepository();
      final bloc = FindRefBloc(findRefRepository: repository);

      bloc.add(const SearchRefRequested('בראשית', includePersonalBooks: false));
      await Future<void>.delayed(_kPastDebounce);

      expect(repository.includePersonalBooksCalls, [false]);
      await bloc.close();
    });
  });

  group('FindRefBloc — זרימת חיפוש', () {
    blocTest<FindRefBloc, FindRefState>(
      'טקסט קצר מדי (תו אחד) מחזיר FindRefSuccess ריק ללא Loading',
      build: _bloc,
      act: (b) => b.add(const SearchRefRequested('א')),
      expect: () => [
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', isEmpty),
      ],
    );

    blocTest<FindRefBloc, FindRefState>(
      'שני תווים — גבול התחתון של החיפוש האמיתי — עובר Loading ואז Success',
      build: () => _bloc(fn: (_) async => [_result()]),
      act: (b) => b.add(const SearchRefRequested('בר')),
      wait: _kPastDebounce,
      expect: () => [
        isA<FindRefLoading>(),
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', hasLength(1)),
      ],
    );

    blocTest<FindRefBloc, FindRefState>(
      'חיפוש תקין מחזיר Loading לפני Success עם תוצאות',
      build: () => _bloc(fn: (_) async => [_result(), _result(title: 'שמות')]),
      act: (b) => b.add(const SearchRefRequested('בראשית')),
      wait: _kPastDebounce,
      expect: () => [
        isA<FindRefLoading>(),
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', hasLength(2)),
      ],
    );

    blocTest<FindRefBloc, FindRefState>(
      'שגיאה במאגר מחזירה FindRefError אחרי Loading',
      build: () => _bloc(error: Exception('DB error')),
      act: (b) => b.add(const SearchRefRequested('בראשית')),
      wait: _kPastDebounce,
      expect: () => [
        isA<FindRefLoading>(),
        isA<FindRefError>().having(
          (s) => s.kind,
          'kind',
          FindRefErrorKind.failed,
        ),
      ],
    );
  });

  group('FindRefBloc — ביטול זר (לא מהקלדה חדשה)', () {
    blocTest<FindRefBloc, FindRefState>(
      'ביטול בלי בקשה חדשה אחריו מריץ ניסיון חוזר ולא נתקע ב-Loading',
      build: () {
        var calls = 0;
        return _bloc(
          fn: (_) async {
            if (calls++ == 0) throw const FindRefQueryCancelled();
            return [_result()];
          },
        );
      },
      act: (b) => b.add(const SearchRefRequested('בראשית')),
      wait: _kTwoDebounces,
      // ה-Loading השני זהה לראשון ולכן bloc אינו פולט אותו שוב.
      expect: () => [
        isA<FindRefLoading>(),
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', hasLength(1)),
      ],
    );

    blocTest<FindRefBloc, FindRefState>(
      'ביטול חוזר על אותה שאילתה נעצר בשגיאה ולא בלולאת ניסיונות',
      build: () => _bloc(error: const FindRefQueryCancelled()),
      act: (b) => b.add(const SearchRefRequested('בראשית')),
      wait: _kTwoDebounces,
      expect: () => [
        isA<FindRefLoading>(),
        const FindRefError(FindRefErrorKind.cancelled),
      ],
    );
  });

  group('FindRefBloc — ניקוי', () {
    blocTest<FindRefBloc, FindRefState>(
      'ClearSearchRequested מחזיר ל-FindRefInitial',
      build: _bloc,
      seed: () => FindRefSuccess([_result()]),
      act: (b) => b.add(ClearSearchRequested()),
      expect: () => [isA<FindRefInitial>()],
    );

    blocTest<FindRefBloc, FindRefState>(
      'חיפוש אחרי ניקוי עובד — FindRefInitial לא חוסם חיפושים עתידיים',
      build: () => _bloc(fn: (_) async => [_result()]),
      act: (b) async {
        b.add(ClearSearchRequested());
        await Future.delayed(Duration.zero);
        b.add(const SearchRefRequested('בראשית'));
      },
      wait: _kPastDebounce,
      expect: () => [
        isA<FindRefInitial>(),
        isA<FindRefLoading>(),
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', hasLength(1)),
      ],
    );
  });
}
