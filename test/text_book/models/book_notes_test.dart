import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';

void main() {
  test('הבונה מקבץ לפי שורה, ו-empty ריק', () {
    final notes =
        (BookNotesBuilder()
              ..add(3, 0, 'א', 'גוף א')
              ..add(3, 1, null, 'נספחת')
              ..add(7, 0, '*', 'גוף'))
            .build();
    expect(notes.isEmpty, isFalse);
    expect(notes.lineCount, 2);
    expect(notes.notesAt(3).map((n) => n.noteIndex), [0, 1]);
    expect(notes.notesAt(4), isEmpty);
    expect(BookNotes.empty.isEmpty, isTrue);
    expect(BookNotesBuilder().build(), same(BookNotes.empty));
  });

  test('toInlineHtml — בצורת notesForLines של הערות inline', () {
    expect(
      BookNotes.toInlineHtml((
        noteIndex: 0,
        charPos: -1,
        marker: 'א',
        body: 'גוף',
      )),
      '<sup class="footnote-marker">א</sup> גוף',
    );
    expect(
      BookNotes.toInlineHtml((
        noteIndex: 1,
        charPos: -1,
        marker: null,
        body: 'גוף',
      )),
      'גוף',
    );
  });

  group('BookNotesRepository', () {
    final repository = BookNotesRepository.instance;
    var loads = 0;
    final loaded = (BookNotesBuilder()..add(0, 0, 'א', 'גוף')).build();

    setUp(() {
      loads = 0;
      repository.clear();
      repository.debugLoader = (title, {categoryId, required source}) async {
        loads++;
        return loaded;
      };
    });
    tearDown(() {
      repository.debugLoader = null;
      repository.clear();
    });

    test('ספר אישי ומהדורה חלופית — ריק, בלי טעינה', () async {
      expect(
        (await repository.notesFor('ספר', source: BookSource.user)).isEmpty,
        isTrue,
      );
      expect(
        (await repository.notesFor('ספר', versionTitle: 'נוסח')).isEmpty,
        isTrue,
      );
      expect(loads, 0);
    });

    test('טעינה אחת לספר, ממטמון', () async {
      expect(await repository.notesFor('ספר', categoryId: 1), same(loaded));
      expect(await repository.notesFor('ספר', categoryId: 1), same(loaded));
      expect(loads, 1);
      repository.clear();
      await repository.notesFor('ספר', categoryId: 1);
      expect(loads, 2);
    });
    test(
      'טאב משוחזר בעלייה: ההערות מחכות לאיתור הספק ולא נשמרות ריקות',
      () async {
        // המיפוי עוד לא נבנה בזמן הקריאה; האיתור מסתיים רק אחריה.
        final providerReady = Completer<bool>();
        repository.debugIsDatabaseBook = (title, {categoryId, fileType}) =>
            providerReady.future;
        addTearDown(() => repository.debugIsDatabaseBook = null);

        final pending = repository.notesFor('ספר', categoryId: 1);
        await Future<void>.delayed(Duration.zero);
        expect(loads, 0);
        providerReady.complete(true);
        expect(await pending, same(loaded));
        expect(await repository.notesFor('ספר', categoryId: 1), same(loaded));
        expect(loads, 1);
      },
    );

    test('ספר שמוגש מקובץ — ריק, בלי טעינה מהמסד', () async {
      repository.debugIsDatabaseBook = (title, {categoryId, fileType}) async =>
          false;
      addTearDown(() => repository.debugIsDatabaseBook = null);
      expect((await repository.notesFor('ספר', categoryId: 1)).isEmpty, isTrue);
      expect(loads, 0);
    });
  });

  test('resolveProviderForBook מאתר ספר שעוד לא מופה, וממפה אותו', () async {
    final manager = LibraryProviderManager.instance;
    final provider = _Provider();
    manager.seedMappingsForTesting(mapping: const {}, providers: [provider]);
    addTearDown(manager.resetForTesting);

    expect(manager.getProviderForBook('ספר', categoryId: 1), isNull);
    expect(
      await manager.resolveProviderForBook('ספר', categoryId: 1),
      same(provider),
    );
    expect(manager.getProviderForBook('ספר', categoryId: 1), same(provider));
  });

  test('rehydrate אידמפוטנטי — החלה שנייה אינה משכפלת את הגוף', () {
    const stored = 'גוף<sup class="footnote-marker">א</sup> סוף';
    final notes =
        (BookNotesBuilder()
              ..add(0, 0, 'א', 'ראשונה')
              ..add(0, 1, null, 'נספחת'))
            .build();
    final once = rehydrateInlineNotes(stored, notes.notesAt(0));
    expect(rehydrateInlineNotes(once, notes.notesAt(0)), once);
    expect(rehydrateInlineNotesInText(once, notes), once);
    expect('class="footnote"'.allMatches(once).length, 2);
  });
}

class _Provider extends Fake implements LibraryProvider {
  @override
  bool get isInitialized => true;

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      title == 'ספר';
}
