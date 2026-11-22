import 'package:bloc_test/bloc_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
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

  @override
  Stream<void> get userBooksChanges => const Stream.empty();

  final Future<List<DbReferenceResult>> Function(String) _fn;
  final Exception? _error;
  final List<bool> includePersonalBooksCalls = [];
  final List<FindRefPreferences?> preferencesCalls = [];

  _FakeRepository({
    Future<List<DbReferenceResult>> Function(String)? fn,
    this._error,
  }) : _fn = fn ?? _emptyFindRefs;

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
    FindRefPreferences? preferences,
  }) async {
    includePersonalBooksCalls.add(includePersonalBooks);
    preferencesCalls.add(preferences);
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

  group('FindRefBloc — התאמה אישית', () {
    const FindRefPreferenceBook book = (key: 'o|1', title: 'בראשית');

    setUp(() async {
      await FindRefPreferenceStore.setEnabled(true);
      FindRefPreferenceStore.clear();
    });

    Future<_FakeRepository> search(SearchRefRequested event) async {
      final repository = _FakeRepository();
      final bloc = FindRefBloc(findRefRepository: repository);
      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);
      await bloc.close();
      return repository;
    }

    test('בקשה שאינה מהדיאלוג (קישור/סיור) אינה מותאמת אישית', () async {
      FindRefPreferenceStore.recordOpen(book);

      final repository = await search(const SearchRefRequested('בראשית'));

      expect(repository.preferencesCalls, [null]);
    });

    test('בקשה מהדיאלוג מעבירה את ההעדפות השמורות', () async {
      FindRefPreferenceStore.recordOpen(book);

      final repository = await search(
        const SearchRefRequested('בראשית', personalized: true),
      );

      expect(repository.preferencesCalls.single!.books.keys, ['o|1']);
    });

    test('מאגר ריק או מתג כבוי: גם הדיאלוג אינו מעביר העדפות', () async {
      final empty = await search(
        const SearchRefRequested('בראשית', personalized: true),
      );
      expect(empty.preferencesCalls, [null]);

      FindRefPreferenceStore.recordOpen(book);
      await FindRefPreferenceStore.setEnabled(false);
      final disabled = await search(
        const SearchRefRequested('בראשית', personalized: true),
      );
      expect(disabled.preferencesCalls, [null]);
    });

    test('פתיחת ספר ומחיקה מרעננות איתור חוזר של אותה שאילתה', () async {
      FindRefPreferenceStore.recordOpen(book);
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);
      const event = SearchRefRequested('בראשית', personalized: true);

      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, hasLength(1));

      // הסדר המוצג נשאר יציב עד שמתבקשת השאילתה שוב.
      FindRefPreferenceStore.recordOpen(book);
      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, hasLength(2));
      expect(
        repository.preferencesCalls.last!.directScore(book.key, book.title),
        1.95,
      );

      FindRefPreferenceStore.clear();
      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, hasLength(3));
      expect(repository.preferencesCalls.last, isNull);

      await bloc.close();
    });

    test('בקשה לא-מותאמת אחרי מותאמת לאותה שאילתה מורצת מחדש', () async {
      FindRefPreferenceStore.recordOpen(book);
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);

      bloc.add(const SearchRefRequested('בראשית', personalized: true));
      await Future<void>.delayed(_kPastDebounce);
      // קישור או סיור: אסור שיקבלו את הסדר המותאם שכבר מוצג.
      bloc.add(const SearchRefRequested('בראשית'));
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, hasLength(2));
      expect(repository.preferencesCalls[0], isNotNull);
      expect(repository.preferencesCalls[1], isNull);

      // הסדר הלא-מותאם שמוצג נשאר גם כשהדיאלוג מבקש שוב את אותה שאילתה.
      bloc.add(const SearchRefRequested('בראשית', personalized: true));
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, hasLength(2));
      await bloc.close();
    });

    test('שחזור הגדרת המתג פוסל את סדר התוצאות השמור', () async {
      FindRefPreferenceStore.recordOpen(book);
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);
      const event = SearchRefRequested('בראשית', personalized: true);

      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);
      await Settings.setValue(FindRefPreferenceStore.enabledKey, false);
      expect(bloc.shownOrderIsStale, isTrue);

      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls.first, isNotNull);
      expect(repository.preferencesCalls.last, isNull);
      await bloc.close();
    });

    test('כבוי ואז דלוק על אותה שאילתה: החיפוש מורץ מחדש עם ההעדפות', () async {
      FindRefPreferenceStore.recordOpen(book);
      await FindRefPreferenceStore.setEnabled(false);
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);
      const event = SearchRefRequested('בראשית', personalized: true);

      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, [null]);

      await FindRefPreferenceStore.setEnabled(true);
      bloc.add(event);
      await Future<void>.delayed(_kPastDebounce);

      expect(repository.preferencesCalls, hasLength(2));
      expect(repository.preferencesCalls.last!.books.keys, ['o|1']);
      await bloc.close();
    });

    test('בקשת הדיאלוג שחוזרת על קישור שטרם הוצג יורשת סדר לא-מותאם', () async {
      FindRefPreferenceStore.recordOpen(book);
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);

      // הקישור עדיין ב-debounce כשהדיאלוג שולח שוב את אותה שאילתה.
      bloc.add(const SearchRefRequested('בראשית'));
      bloc.add(const SearchRefRequested('בראשית ', personalized: true));
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, [null]);
      expect(bloc.shownOrderIsStale, isFalse);

      // שאילתה אחרת מהדיאלוג מותאמת כרגיל.
      bloc.add(const SearchRefRequested('שמות', personalized: true));
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, hasLength(2));
      expect(repository.preferencesCalls.last, isNotNull);
      await bloc.close();
    });

    test('קישור שנכשל אינו מבטל את ההתאמה של "נסה שוב" מהדיאלוג', () async {
      FindRefPreferenceStore.recordOpen(book);
      final repository = _FakeRepository(error: Exception('not ready'));
      final bloc = FindRefBloc(findRefRepository: repository);

      bloc.add(const SearchRefRequested('בראשית'));
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, [null]);

      bloc.add(const SearchRefRequested('בראשית', personalized: true));
      await Future<void>.delayed(_kPastDebounce);
      expect(repository.preferencesCalls, hasLength(2));
      expect(repository.preferencesCalls.last, isNotNull);
      await bloc.close();
    });

    test('קישור לשאילתה אחת אינו מבטל התאמה של שאילתה אחרת', () async {
      FindRefPreferenceStore.recordOpen(book);
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);

      bloc.add(const SearchRefRequested('בראשית'));
      bloc.add(const SearchRefRequested('שמות', personalized: true));
      await Future<void>.delayed(_kPastDebounce);

      expect(repository.preferencesCalls.single, isNotNull);
      await bloc.close();
    });

    test('shownOrderIsStale: רק סדר מותאם שההעדפות שלו השתנו מאז', () async {
      FindRefPreferenceStore.recordOpen(book);
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);
      expect(bloc.shownOrderIsStale, isFalse);

      bloc.add(const SearchRefRequested('בראשית', personalized: true));
      await Future<void>.delayed(_kPastDebounce);
      FindRefPreferenceStore.recordOpen(book);
      expect(bloc.shownOrderIsStale, isTrue);

      await FindRefPreferenceStore.setEnabled(false);
      expect(bloc.shownOrderIsStale, isTrue);

      bloc.add(const SearchRefRequested('בראשית', personalized: true));
      await Future<void>.delayed(_kPastDebounce);
      expect(bloc.shownOrderIsStale, isFalse);
      expect(repository.preferencesCalls.last, isNull);

      // סדר לא-מותאם אינו מתיישן משינוי בהעדפות.
      bloc.add(const SearchRefRequested('שמות'));
      await Future<void>.delayed(_kPastDebounce);
      FindRefPreferenceStore.clear();
      expect(bloc.shownOrderIsStale, isFalse);
      await bloc.close();
    });

    test('תוצאות לא-מותאמות אינן מורצות מחדש בגלל שינוי בהעדפות', () async {
      final repository = _FakeRepository(fn: (_) async => [_result()]);
      final bloc = FindRefBloc(findRefRepository: repository);

      bloc.add(const SearchRefRequested('בראשית'));
      await Future<void>.delayed(_kPastDebounce);
      FindRefPreferenceStore.clear();
      bloc.add(const SearchRefRequested('בראשית'));
      await Future<void>.delayed(_kPastDebounce);

      expect(repository.preferencesCalls, [null]);
      await bloc.close();
    });
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
