import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

// בדיקות אינטגרציה של ה-debounce + restartable ברמת ה-bloc.
// ה-debounce חי בתוך `_onSearchRefRequested` (await Future.delayed לפני
// כל עבודה כבדה), ו-`restartable()` מבטל handler קודם בנקודת ה-await
// הראשונה. כך כל הקלדה חדשה מאפסת את הדיליי וגם מבטלת fetch שעדיין רץ.

const _kPastDebounce = Duration(milliseconds: 350);
const _kBelowDebounce = Duration(milliseconds: 100);

/// מחקה את `FindRefRepository.findRefs` בלבד; שאר ה-API לא בשימוש בטסטים
/// האלו. כל קריאה נרשמת ב-[calls] ומחזירה ריק.
class _RecordingRepo extends FindRefRepository {
  _RecordingRepo();

  final List<String> calls = <String>[];

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    calls.add(ref);
    return const [];
  }
}

void main() {
  group('FindRefBloc — debounce + restartable', () {
    test('debounce: הקלדה אחת — findRefs רץ אחרי השהיה של ~250ms', () async {
      final repo = _RecordingRepo();
      final bloc = FindRefBloc(findRefRepository: repo);

      bloc.add(const SearchRefRequested('אב'));

      // לפני הדיליי — שום fetch לא התחיל.
      await Future.delayed(_kBelowDebounce);
      expect(repo.calls, isEmpty);

      // אחרי הדיליי — fetch אחד.
      await Future.delayed(_kPastDebounce);
      expect(repo.calls, ['אב']);

      await bloc.close();
    });

    test('הקלדה מהירה — רק האחרונה מגיעה ל-findRefs', () async {
      final repo = _RecordingRepo();
      final bloc = FindRefBloc(findRefRepository: repo);

      // שלוש הקלדות תוך פחות מדיליי אחד.
      bloc.add(const SearchRefRequested('אב'));
      await Future.delayed(const Duration(milliseconds: 50));
      bloc.add(const SearchRefRequested('אבג'));
      await Future.delayed(const Duration(milliseconds: 50));
      bloc.add(const SearchRefRequested('אבגד'));

      // ממתינים יותר מדיליי מהאירוע האחרון.
      await Future.delayed(_kPastDebounce);

      expect(repo.calls, ['אבגד']);
      await bloc.close();
    });

    test('שאילתה < 2 תווים — לא מפעילה findRefs ולא ממתינה לדיליי', () async {
      final repo = _RecordingRepo();
      final bloc = FindRefBloc(findRefRepository: repo);

      final states = <FindRefState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const SearchRefRequested('א'));
      // אין צורך להמתין לדיליי — הקצרצרה צריכה להחזיר Success([]) מיידית.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(repo.calls, isEmpty);
      expect(states.last, isA<FindRefSuccess>());
      expect((states.last as FindRefSuccess).refs, isEmpty);

      await sub.cancel();
      await bloc.close();
    });

    test('הקלדה חדשה תוך כדי fetch — מבטלת את התוצאה הישנה', () async {
      // ה-gate הראשון אינו נסגר עד שהטסט משחרר אותו; כך אנו מדמים fetch
      // ארוך שעוד תקוע כשהמשתמש מקליד שוב.
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();

      var fetchIndex = 0;
      final calls = <String>[];
      final repo = _SequentialGateRepo(
        gates: [firstGate.future, secondGate.future],
        onCall: (q) {
          calls.add(q);
          fetchIndex++;
        },
      );

      final bloc = FindRefBloc(findRefRepository: repo);

      final successes = <List<DbReferenceResult>>[];
      final sub = bloc.stream.listen((s) {
        if (s is FindRefSuccess) successes.add(s.refs);
      });

      // אירוע ראשון: ממתין דיליי, ואז מתחיל fetch שתקוע ב-firstGate.
      bloc.add(const SearchRefRequested('אבג'));
      await Future.delayed(_kPastDebounce);
      expect(calls, ['אבג'], reason: 'ה-fetch הראשון התחיל');

      // אירוע חדש לפני ש-firstGate נסגר → restartable מבטל את ה-handler הישן.
      bloc.add(const SearchRefRequested('אבגד'));
      await Future.delayed(_kPastDebounce);
      expect(calls, ['אבג', 'אבגד'], reason: 'ה-fetch השני התחיל');

      // משחררים את ה-fetch הראשון. ה-handler שלו בוטל ב-emit.isDone — לא
      // אמורות להירשם תוצאות.
      firstGate.complete();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(
        successes,
        isEmpty,
        reason: 'תוצאה של fetch מבוטל לא צריכה להיכתב ל-state',
      );

      // משחררים את ה-fetch השני — זה כן צריך לדווח.
      secondGate.complete();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(successes, hasLength(1));

      await sub.cancel();
      await bloc.close();
      expect(fetchIndex, 2);
    });

    test('הקלדה חדשה במהלך ה-debounce של הקודמת — רק האחרונה מגיעה', () async {
      final repo = _RecordingRepo();
      final bloc = FindRefBloc(findRefRepository: repo);

      bloc.add(const SearchRefRequested('אבג'));
      await Future.delayed(_kBelowDebounce); // עדיין בתוך הדיליי
      bloc.add(const SearchRefRequested('אבגד'));
      await Future.delayed(_kPastDebounce);

      // ה-handler הראשון בוטל ב-await Future.delayed שלו — שום fetch לא יצא.
      expect(repo.calls, ['אבגד']);

      await bloc.close();
    });

    test('רווח נגרר אינו מריץ חיפוש מחדש ואינו מהבהב ספינר', () async {
      final repo = _RecordingRepo();
      final bloc = FindRefBloc(findRefRepository: repo);
      final states = <FindRefState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const SearchRefRequested('שולחן'));
      await Future.delayed(_kPastDebounce);
      expect(repo.calls, ['שולחן']);
      expect(states.whereType<FindRefLoading>(), hasLength(1));

      // רווח, גרשיים ופיסוק נעלמים בנרמול — אותה שאילתה בדיוק.
      bloc.add(const SearchRefRequested('שולחן '));
      bloc.add(const SearchRefRequested('שולחן  '));
      bloc.add(const SearchRefRequested('שולחן",'));
      await Future.delayed(_kPastDebounce);

      expect(repo.calls, ['שולחן'], reason: 'אין fetch נוסף');
      expect(
        states.whereType<FindRefLoading>(),
        hasLength(1),
        reason: 'אין ספינר שני על אותן תוצאות',
      );

      // שינוי אמיתי כן מריץ.
      bloc.add(const SearchRefRequested('שולחן ערוך'));
      await Future.delayed(_kPastDebounce);
      expect(repo.calls, ['שולחן', 'שולחן ערוך']);

      await sub.cancel();
      await bloc.close();
    });

    test('אותה שאילתה כן רצה שוב כשהמצב אינו תוצאות', () async {
      final repo = _RecordingRepo();
      final bloc = FindRefBloc(findRefRepository: repo);

      bloc.add(const SearchRefRequested('שולחן'));
      await Future.delayed(_kPastDebounce);
      expect(repo.calls, ['שולחן']);

      // ניקוי מחזיר את המצב ל-Initial — הקלדה חוזרת חייבת לטעון מחדש.
      bloc.add(ClearSearchRequested());
      await Future.delayed(const Duration(milliseconds: 20));
      bloc.add(const SearchRefRequested('שולחן'));
      await Future.delayed(_kPastDebounce);
      expect(repo.calls, ['שולחן', 'שולחן']);

      await bloc.close();
    });
  });
}

/// repository שמדמה fetch שמשתחרר ידנית. כל קריאה ל-`findRefs` ממתינה
/// ל-gate הבא בתור.
class _SequentialGateRepo extends FindRefRepository {
  _SequentialGateRepo({required this.gates, required this.onCall});

  final List<Future<void>> gates;
  final void Function(String query) onCall;
  int _index = 0;

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    onCall(ref);
    final gate = gates[_index++];
    await gate;
    return const [];
  }
}
