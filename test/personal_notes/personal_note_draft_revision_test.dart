import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../test_helpers/memory_cache_provider.dart';

class _DelayedDraftCache extends MemoryCacheProvider {
  Completer<void>? pointWriteGate;
  Completer<void>? removeGate;
  bool gatedPointWrite = false;
  bool failRemove = false;

  @override
  Future<void> setObject<T>(String key, T? value) async {
    final write = super.setObject<T>(key, value);
    if (pointWriteGate != null && key.contains(':pdf:') && !gatedPointWrite) {
      gatedPointWrite = true;
      await pointWriteGate!.future;
    }
    await write;
  }

  @override
  Future<void> remove(String key) async {
    if (failRemove) throw StateError('draft removal failed');
    final removal = super.remove(key);
    await removeGate?.future;
    await removal;
  }
}

void main() {
  final first = PersonalNoteDraftService();
  final second = PersonalNoteDraftService();
  late _DelayedDraftCache cache;
  late String bookId;
  var sequence = 0;
  const line = 4;
  const point = PdfNoteAnchor(pageNumber: line, x: .2, y: .3);

  PersonalNoteDraft draft(String content, {PdfNoteAnchor? anchor}) =>
      PersonalNoteDraft(
        content: content,
        contentPlain: content,
        contentFormat: PersonalNoteContentFormat.plain,
        // אותו זמן גם בכתיבות שונות: ההגנה אינה תלויה בשעון או בתוכן.
        updatedAt: DateTime.utc(2026),
        lineNumber: line,
        pdfAnchor: anchor,
      );

  Future<void> legacyPdf() => Settings.setValue<String>(
    '${PersonalNoteDraftService.keyPrefix}$bookId:$line',
    jsonEncode(draft('טיוטת PDF ישנה', anchor: point).toJson()),
  );

  Future<void> write(
    PersonalNoteDraftService service,
    String content, {
    PdfNoteAnchor? anchor,
  }) => service.saveDraft(
    bookId: bookId,
    lineNumber: line,
    draft: draft(content, anchor: anchor),
  );

  Future<PersonalNoteDraft?> read({PdfNoteAnchor? anchor}) => first.loadDraft(
    bookId: bookId,
    lineNumber: line,
    pdfAnchor: anchor,
  );

  Object? version({PdfNoteAnchor? anchor}) => first.draftVersion(
    bookId: bookId,
    lineNumber: line,
    pdfAnchor: anchor,
  );

  setUp(() async {
    cache = _DelayedDraftCache();
    bookId = 'draft-revision-${sequence++}';
    await Settings.init(cacheProvider: cache);
  });

  tearDown(() {
    for (final gate in [cache.pointWriteGate, cache.removeGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
  });

  test(
    'conditional clear preserves a newer identical draft from another service',
    () async {
      await write(first, 'אותו תוכן');
      final savedVersion = version();
      await write(second, 'אותו תוכן');
      expect(identical(version(), savedVersion), isFalse);
      await first.clearDraft(
        bookId: bookId,
        lineNumber: line,
        expectedVersion: savedVersion,
      );
      expect((await read())?.contentPlain, 'אותו תוכן');
    },
  );

  test(
    'an absent revision is conditional while omitted revision clears explicitly',
    () async {
      await Settings.setValue<String>(
        '${PersonalNoteDraftService.keyPrefix}$bookId:$line',
        jsonEncode(draft('טיוטה מתהליך קודם').toJson()),
      );
      expect(version(), isNull);
      await write(second, 'טיוטה חדשה');
      await first.clearDraft(
        bookId: bookId,
        lineNumber: line,
        expectedVersion: null,
      );
      expect((await read())?.contentPlain, 'טיוטה חדשה');
      await first.clearDraft(bookId: bookId, lineNumber: line);
      expect(await read(), isNull);
    },
  );

  test(
    'clear during legacy migration cancels pending text without deleting PDF',
    () async {
      await legacyPdf();
      final gate = cache.pointWriteGate = Completer<void>();
      final pending = write(first, 'טקסט שבוטל');
      expect(cache.gatedPointWrite, isTrue);
      await second.clearDraft(
        bookId: bookId,
        lineNumber: line,
        expectedVersion: version(),
      );
      gate.complete();
      await pending;

      expect(await read(), isNull);
      expect((await read(anchor: point))?.contentPlain, 'טיוטת PDF ישנה');
    },
  );

  test(
    'old migration does not delete a newer text draft in the legacy key',
    () async {
      await legacyPdf();
      final gate = cache.pointWriteGate = Completer<void>();
      final pending = write(first, 'טקסט ישן');
      expect(cache.gatedPointWrite, isTrue);
      await write(second, 'טקסט חדש');
      gate.complete();
      await pending;

      expect((await read())?.contentPlain, 'טקסט חדש');
      expect((await read(anchor: point))?.contentPlain, 'טיוטת PDF ישנה');
    },
  );

  test(
    'old migration preserves a newer PDF draft in the copied point key',
    () async {
      await legacyPdf();
      const anotherPoint = PdfNoteAnchor(pageNumber: line, x: .7, y: .8);
      final gate = cache.pointWriteGate = Completer<void>();
      final pending = write(first, 'נקודה אחרת', anchor: anotherPoint);
      expect(cache.gatedPointWrite, isTrue);
      await write(second, 'נקודה שהתעדכנה', anchor: point);
      gate.complete();
      await pending;

      expect((await read(anchor: point))?.contentPlain, 'נקודה שהתעדכנה');
      expect((await read(anchor: anotherPoint))?.contentPlain, 'נקודה אחרת');
      expect(await read(), isNull);
    },
  );

  test(
    'delayed PDF cleanup cannot restore its legacy copy through a text writer',
    () async {
      await write(first, 'טיוטת PDF ישנה', anchor: point);
      await legacyPdf();
      final gate = cache.removeGate = Completer<void>();
      final cleanup = first.clearDraft(
        bookId: bookId,
        lineNumber: line,
        pdfAnchor: point,
        expectedVersion: version(anchor: point),
      );
      // שתי המחיקות כבר נראות במטמון; רק אישור ה-flush מושהה.
      expect(await read(anchor: point), isNull);
      await write(second, 'טקסט חדש');
      gate.complete();
      await cleanup;

      expect((await read())?.contentPlain, 'טקסט חדש');
      expect(await read(anchor: point), isNull);
    },
  );

  test('a failed clear retains its revision for a later retry', () async {
    await write(first, 'טיוטה למחיקה');
    final savedVersion = version();
    cache.failRemove = true;
    await expectLater(
      first.clearDraft(
        bookId: bookId,
        lineNumber: line,
        expectedVersion: savedVersion,
      ),
      throwsStateError,
    );
    expect(identical(version(), savedVersion), isTrue);
    cache.failRemove = false;
    await first.clearDraft(
      bookId: bookId,
      lineNumber: line,
      expectedVersion: savedVersion,
    );
    expect(await read(), isNull);
  });
}
