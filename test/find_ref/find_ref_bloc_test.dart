import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

// ─── Fake repository ──────────────────────────────────────────────────────────
// implements (לא extends) — אין צורך ב-DataRepository, BLoC קורא רק findRefs

Future<List<DbReferenceResult>> _emptyFindRefs(String _) async => const [];

class _FakeRepository implements FindRefRepository {
  final Future<List<DbReferenceResult>> Function(String) _fn;
  final Exception? _error;

  _FakeRepository({
    Future<List<DbReferenceResult>> Function(String)? fn,
    Exception? error,
  })  : _fn = fn ?? _emptyFindRefs,
        _error = error;

  @override
  Future<List<DbReferenceResult>> findRefs(String ref) async {
    if (_error != null) throw _error;
    return _fn(ref);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

DbReferenceResult _result({
  String title = 'בראשית',
  String ref = 'בראשית פרק א',
}) =>
    DbReferenceResult(title: title, reference: ref, segment: 1);

FindRefBloc _bloc({
  Future<List<DbReferenceResult>> Function(String)? fn,
  Exception? error,
}) =>
    FindRefBloc(
      findRefRepository: _FakeRepository(fn: fn, error: error),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect: () => [
        isA<FindRefLoading>(),
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', hasLength(1)),
      ],
    );

    blocTest<FindRefBloc, FindRefState>(
      'חיפוש תקין מחזיר Loading לפני Success עם תוצאות',
      build: () => _bloc(fn: (_) async => [_result(), _result(title: 'שמות')]),
      act: (b) => b.add(const SearchRefRequested('בראשית')),
      expect: () => [
        isA<FindRefLoading>(),
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', hasLength(2)),
      ],
    );

    blocTest<FindRefBloc, FindRefState>(
      'שגיאה במאגר מחזירה FindRefError אחרי Loading',
      build: () => _bloc(error: Exception('DB error')),
      act: (b) => b.add(const SearchRefRequested('בראשית')),
      expect: () => [
        isA<FindRefLoading>(),
        isA<FindRefError>().having((s) => s.message, 'message', contains('DB error')),
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
      expect: () => [
        isA<FindRefInitial>(),
        isA<FindRefLoading>(),
        isA<FindRefSuccess>().having((s) => s.refs, 'refs', hasLength(1)),
      ],
    );
  });
}
