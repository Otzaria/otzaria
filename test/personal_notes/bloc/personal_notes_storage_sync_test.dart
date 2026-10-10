import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';

/// מאגר בזיכרון שמודיע על כתיבות כמו המסד האמיתי.
class _MemoryRepository implements PersonalNotesRepository {
  final store = <String, List<PersonalNote>>{};
  int loadCalls = 0;

  /// כשמוגדר, טעינה מלאה ממתינה לו — כמו קריאת תוכן ספר גדול.
  Completer<void>? loadGate;

  /// כמו [loadGate], לקריאת ההערות השמורות שמשווים מולה.
  Completer<void>? storedGate;

  /// הטעינה המלאה הבאה נכשלת (אחרי [loadGate]).
  bool failNextLoad = false;

  /// כתיבה שלא עברה דרך ה-bloc — כמו דיאלוג הערת המפרש בצורת הדף.
  void writeExternally(String bookId, List<PersonalNote> notes) {
    store[bookId] = notes;
    PersonalNotesChanges.notify(bookId);
  }

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) async {
    loadCalls++;
    final snapshot = List.of(store[bookId] ?? const <PersonalNote>[]);
    final fail = failNextLoad;
    failNextLoad = false;
    await loadGate?.future;
    if (fail) throw Exception('קריאת הספר נכשלה');
    return snapshot;
  }

  @override
  Future<List<PersonalNote>> loadStoredNotes(String bookId) async {
    await storedGate?.future;
    return List.of(store[bookId] ?? const []);
  }

  @override
  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String noteId,
    int? categoryId,
  }) async {
    store[bookId] = [
      for (final note in store[bookId] ?? const <PersonalNote>[])
        if (note.id != noteId) note,
    ];
    PersonalNotesChanges.notify(bookId);
    return List.of(store[bookId]!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _MemoryRepository repository;
  late PersonalNotesBloc bloc;

  setUp(() async {
    repository = _MemoryRepository()..store['רש"י'] = [_note('1')];
    bloc = PersonalNotesBloc(repository: repository);
    bloc.add(const LoadPersonalNotes('רש"י', categoryId: 9));
    await pumpEventQueue();
    expect(bloc.state.locatedNotes.map((n) => n.id), ['1']);
  });

  tearDown(() => bloc.close());

  test('הערה שנוספה מחוץ ל-bloc מופיעה בחלונית בלי טעינה ידנית', () async {
    repository.writeExternally('רש"י', [_note('1'), _note('2', line: 3)]);
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((n) => n.id), ['1', '2']);
    expect(bloc.state.categoryId, 9, reason: 'הטעינה מחדש שומרת את הקטגוריה');
  });

  test('הערה שנמחקה מחוץ ל-bloc נעלמת מהחלונית', () async {
    repository.writeExternally('רש"י', const []);
    await pumpEventQueue();

    expect(bloc.state.locatedNotes, isEmpty);
  });

  test('שינוי בספר אחר אינו טוען מחדש את הספר המוצג', () async {
    final callsBefore = repository.loadCalls;

    repository.writeExternally('תוספות', [_note('9')]);
    await pumpEventQueue();

    expect(repository.loadCalls, callsBefore);
    expect(bloc.state.locatedNotes.map((n) => n.id), ['1']);
  });

  test('מחיקה דרך ה-bloc עצמו אינה גורמת לטעינה כפולה', () async {
    final callsBefore = repository.loadCalls;

    bloc.add(const DeletePersonalNote(bookId: 'רש"י', noteId: '1'));
    await pumpEventQueue();

    expect(bloc.state.locatedNotes, isEmpty);
    expect(
      repository.loadCalls,
      callsBefore,
      reason: 'התוצאה של המחיקה כבר ב-state; טעינה נוספת קוראת שוב את הספר',
    );
  });

  test('כתיבה זהה למה שכבר מוצג אינה טוענת מחדש', () async {
    final callsBefore = repository.loadCalls;

    repository.writeExternally('רש"י', [_note('1')]);
    await pumpEventQueue();

    expect(repository.loadCalls, callsBefore);
  });

  test('שינוי שמגיע בזמן טעינה נקלט כשהיא מסתיימת', () async {
    repository.loadGate = Completer<void>();
    bloc.add(const LoadPersonalNotes('רש"י', categoryId: 9));
    await pumpEventQueue();
    expect(bloc.state.isLoading, isTrue);

    // הטעינה כבר קראה את המאגר; הכתיבה מגיעה אחריה.
    repository.writeExternally('רש"י', [_note('1'), _note('2', line: 3)]);
    await pumpEventQueue();
    repository.loadGate!.complete();
    repository.loadGate = null;
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((n) => n.id), ['1', '2']);
  });

  test('רענון רקע אינו מבטל טעינה של ספר אחר שנשלחה בינתיים', () async {
    repository.store['תוספות'] = [_note('7')];
    repository.storedGate = Completer<void>();
    repository.writeExternally('רש"י', const []);
    await pumpEventQueue();

    // הרענון ממשיך רגע אחרי שנשלחה בקשה לספר אחר, לפני שהיא התחילה.
    repository.storedGate!.complete();
    repository.storedGate = null;
    bloc.add(const LoadPersonalNotes('תוספות'));
    await pumpEventQueue();

    expect(bloc.state.bookId, 'תוספות');
    expect(bloc.state.locatedNotes.map((n) => n.id), ['7']);
  });

  test('מחיקה בזמן רענון רקע אינה מוחזרת על ידי תוצאת הרענון', () async {
    repository.loadGate = Completer<void>();
    repository.writeExternally('רש"י', [_note('1'), _note('2', line: 3)]);
    await pumpEventQueue();

    final gate = repository.loadGate!;
    repository.loadGate = null;
    bloc.add(const DeletePersonalNote(bookId: 'רש"י', noteId: '2'));
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((n) => n.id), ['1']);
  });

  test('רענון שמסתיים אחרי מעבר לספר אחר אינו מחזיר את הספר הקודם', () async {
    repository.store['תוספות'] = [_note('7')];
    final gate = Completer<void>();
    repository.loadGate = gate;
    repository.writeExternally('רש"י', const []);
    await pumpEventQueue();

    repository.loadGate = null;
    bloc.add(const LoadPersonalNotes('תוספות'));
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    expect(bloc.state.bookId, 'תוספות');
    expect(bloc.state.locatedNotes.map((n) => n.id), ['7']);
  });

  test('רענון רקע אינו מסיים טעינה של אותו ספר שעוד רצה', () async {
    final refreshGate = Completer<void>();
    repository.loadGate = refreshGate;
    repository.writeExternally('רש"י', [_note('1'), _note('2', line: 2)]);
    await pumpEventQueue();
    final loadGate = Completer<void>();
    repository.loadGate = loadGate;
    bloc.add(const LoadPersonalNotes('רש"י', categoryId: 9));
    await pumpEventQueue();

    refreshGate.complete();
    await pumpEventQueue();
    expect(bloc.state.isLoading, isTrue, reason: 'הטעינה עדיין רצה');

    // כתיבה אחרי שהטעינה כבר קראה את המאגר.
    repository.loadGate = null;
    repository.writeExternally('רש"י', [
      _note('1'),
      _note('2', line: 2),
      _note('3', line: 3),
    ]);
    await pumpEventQueue();
    loadGate.complete();
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((n) => n.id), ['1', '2', '3']);
  });

  test('שינוי שהגיע בזמן טעינה שנכשלה נקלט בכל זאת', () async {
    final gate = Completer<void>();
    repository
      ..loadGate = gate
      ..failNextLoad = true;
    bloc.add(const LoadPersonalNotes('רש"י', categoryId: 9));
    await pumpEventQueue();
    repository.writeExternally('רש"י', [_note('1'), _note('2', line: 2)]);
    await pumpEventQueue();

    repository.loadGate = null;
    gate.complete();
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((n) => n.id), ['1', '2']);
  });

  test('טעינה שבוטלה אינה צורכת שינוי שנועד לספר שהחליף אותה', () async {
    repository.store['תוספות'] = [_note('5')];
    final cancelledGate = Completer<void>();
    repository.loadGate = cancelledGate;
    bloc.add(const LoadPersonalNotes('רש"י', categoryId: 9));
    await pumpEventQueue();
    final loadGate = Completer<void>();
    repository.loadGate = loadGate;
    bloc.add(const LoadPersonalNotes('תוספות'));
    await pumpEventQueue();

    repository.loadGate = null;
    repository.writeExternally('תוספות', [_note('5'), _note('6', line: 2)]);
    await pumpEventQueue();
    cancelledGate.complete();
    loadGate.complete();
    await pumpEventQueue();

    expect(bloc.state.bookId, 'תוספות');
    expect(bloc.state.locatedNotes.map((n) => n.id), ['5', '6']);
  });

  test('שגיאה בקריאת המסד ברענון רקע משאירה את ההערות המוצגות', () async {
    final gate = Completer<void>();
    repository
      ..loadGate = gate
      ..failNextLoad = true;
    repository.writeExternally('רש"י', const []);
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((n) => n.id), ['1']);
    expect(bloc.state.errorMessage, isNull);
  });

  test('רענון ישן שמסתיים אחרי רענון חדש אינו דורס אותו', () async {
    final staleGate = Completer<void>();
    repository.loadGate = staleGate;
    repository.writeExternally('רש"י', [_note('1'), _note('2', line: 2)]);
    await pumpEventQueue();

    repository.loadGate = null;
    repository.writeExternally('רש"י', [
      _note('1'),
      _note('2', line: 2),
      _note('3', line: 3),
    ]);
    await pumpEventQueue();
    staleGate.complete();
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((n) => n.id), ['1', '2', '3']);
  });

  test('הודעה שמגיעה אחרי סגירת ה-bloc אינה זורקת', () async {
    await bloc.close();

    repository.writeExternally('רש"י', const []);
    await pumpEventQueue();

    expect(bloc.isClosed, isTrue);
  });
}

PersonalNote _note(String id, {int line = 1}) {
  final now = DateTime(2026, 10, 4);
  return PersonalNote(
    id: id,
    bookId: 'רש"י',
    lineNumber: line,
    displayTitle: 'שורה',
    lastKnownLineNumber: line,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}
