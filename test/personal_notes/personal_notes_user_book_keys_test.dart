import 'dart:async';
import 'dart:io';

import 'package:otzaria/data/sqlite/sqlite3_api.dart';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_user_book_keys.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

Library _library(List<Book> books) {
  final category = Category(
    title: 'root',
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: books,
    parent: null,
  );
  final library = Library(categories: [category]);
  category.parent = library;
  return library;
}

PersonalNote _note(String id, String bookId, int line, String text) {
  final now = DateTime(2026, 1, 1);
  return PersonalNote(
    id: id,
    bookId: bookId,
    lineNumber: line,
    displayTitle: text,
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: 'תוכן $id',
    contentPlain: 'תוכן $id',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;

  final officialBeitza = TextBook(id: 1, title: 'ביצה', categoryId: 1);
  final userBeitza = TextBook(
    id: 1,
    title: 'ביצה',
    categoryId: 1,
    source: BookSource.user,
  );
  final userOnly = TextBook(id: 2, title: 'יומן', source: BookSource.user);
  final contents = <String, String>{
    'ביצה': 'ביצה שנולדה ביום טוב\nבית שמאי אומרים\nטקסט משותף',
    'ביצה|user': 'הערות שלי\nשורה אישית ייחודית\nטקסט משותף',
    'יומן|user': 'רשימה ראשונה',
  };

  PersonalNotesUserBookKeys migration({
    Map<String, String>? content,
    String catalogVersion = 'unknown',
  }) => PersonalNotesUserBookKeys(
    loadContent: (book) async =>
        (content ?? contents)[personalNotesBookKey(book)] ?? '',
    catalogVersion: () async => catalogVersion,
  );

  Future<Set<String>> idsUnder(String key) async =>
      (await database.loadNotes(key)).map((n) => n.id).toSet();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('notes_user_keys_test_');
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
  });

  tearDown(() async {
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  test('a legacy note moves to the user book only when its text is on that '
      'line there and not in the official book', () async {
    await database.insertNote(_note('user', 'ביצה', 2, 'שורה אישית ייחודית'));
    await database.insertNote(_note('official', 'ביצה', 1, 'שנולדה ביום טוב'));
    await database.insertNote(_note('both', 'ביצה', 3, 'טקסט משותף'));
    await database.insertNote(_note('neither', 'ביצה', 1, 'מילים שאינן'));

    await migration().assignPending(
      _library([officialBeitza, userBeitza, userOnly]),
    );

    expect(await idsUnder('ביצה|user'), {'user'});
    expect(await idsUnder('ביצה'), {'official', 'both', 'neither'});
    expect(await database.userBookKeysPending(), isFalse);
  });

  test('a title that exists only as a user book moves all its notes', () async {
    await database.insertNote(_note('a', 'יומן', 1, 'רשימה ראשונה'));
    await database.insertNote(_note('b', 'יומן', 7, 'לא בספר'));

    await migration().assignPending(_library([officialBeitza, userOnly]));

    expect(await idsUnder('יומן|user'), {'a', 'b'});
    expect(await idsUnder('יומן'), isEmpty);
  });

  test('runs once; an import marks it pending again', () async {
    final library = _library([officialBeitza, userBeitza]);
    await migration().assignPending(library);
    await database.insertNote(_note('late', 'ביצה', 2, 'שורה אישית ייחודית'));

    await migration().assignPending(library);
    expect(await idsUnder('ביצה'), {'late'});

    await database.setUserBookKeysPending(true);
    await migration().assignPending(library);
    expect(await idsUnder('ביצה|user'), {'late'});
  });

  test('without the text of both books nothing moves', () async {
    await database.insertNote(_note('user', 'ביצה', 2, 'שורה אישית ייחודית'));

    await migration(
      content: {'ביצה|user': contents['ביצה|user']!},
    ).assignPending(_library([officialBeitza, userBeitza]));

    expect(await idsUnder('ביצה'), {'user'});
  });

  test('a loaded library with only user books migrates its notes', () async {
    await database.insertNote(_note('a', 'יומן', 1, 'רשימה ראשונה'));

    await migration().assignPending(_library([userOnly]));

    expect(await idsUnder('יומן'), isEmpty);
    expect(await idsUnder('יומן|user'), {'a'});
    expect(await database.userBookKeysPending(), isFalse);
  });

  test('notes already keyed by source are left alone', () async {
    await database.insertNote(
      _note('attached', 'ביצה|db:lib-a', 2, 'שורה אישית ייחודית'),
    );
    await database.insertNote(_note('mine', 'ביצה|user', 1, 'הערות שלי'));

    await migration().assignPending(_library([officialBeitza, userBeitza]));

    expect(await idsUnder('ביצה|db:lib-a'), {'attached'});
    expect(await idsUnder('ביצה|user'), {'mine'});
  });
  test(
    'missing book content keeps migration pending for a later retry',
    () async {
      await database.insertNote(_note('user', 'ביצה', 2, 'שורה אישית ייחודית'));
      final library = _library([officialBeitza, userBeitza]);

      await migration(
        content: {'ביצה': contents['ביצה']!},
      ).assignPending(library);
      expect(await database.userBookKeysPending(), isTrue);
      await migration().assignPending(library);

      expect(await idsUnder('ביצה|user'), {'user'});
      expect(await database.userBookKeysPending(), isFalse);
    },
  );

  test(
    'a secondary personal text version is migrated instead of its PDF',
    () async {
      await database.insertNote(_note('user', 'ביצה', 2, 'שורה אישית ייחודית'));
      final library = _library([
        officialBeitza,
        PdfBook(title: 'ביצה', path: '/ביצה.pdf', source: BookSource.user),
      ])..offTreeBooks = [userBeitza];
      final loaded = <Book>[];
      await PersonalNotesUserBookKeys(
        loadContent: (book) async {
          loaded.add(book);
          return contents[personalNotesBookKey(book)]!;
        },
      ).assignPending(library);

      expect(loaded, [officialBeitza, userBeitza]);
      expect(await idsUnder('ביצה|user'), {'user'});
    },
  );

  test('PDF ambiguity is final and does not load book text', () async {
    await database.insertNote(_note('pdf', 'ביצה', 2, 'שורה אישית ייחודית'));
    final pdf = PdfBook(
      title: 'ביצה',
      path: '/ביצה.pdf',
      source: BookSource.user,
    );
    await PersonalNotesUserBookKeys(
      loadContent: (_) async {
        fail('PDF notes cannot be assigned by matching text');
      },
    ).assignPending(_library([officialBeitza, pdf]));

    expect(await idsUnder('ביצה'), {'pdf'});
    expect(await database.userBookKeysPending(), isFalse);
  });

  test(
    'an import during content loading is assigned after the current run',
    () async {
      await database.insertNote(
        _note('first', 'ביצה', 2, 'שורה אישית ייחודית'),
      );
      final loading = Completer<void>();
      final release = Completer<void>();
      final first = PersonalNotesUserBookKeys(
        loadContent: (book) async {
          if (!loading.isCompleted) {
            loading.complete();
            await release.future;
          }
          return contents[personalNotesBookKey(book)]!;
        },
      ).assignPending(_library([officialBeitza, userBeitza, userOnly]));
      await loading.future;
      await database.batchInsertNotes([
        _note('imported', 'יומן', 1, 'רשימה ראשונה'),
      ]);
      final imported = migration().assignPending(
        _library([officialBeitza, userBeitza, userOnly]),
      );
      release.complete();
      await Future.wait([first, imported]);

      expect(await idsUnder('ביצה|user'), {'first'});
      expect(await idsUnder('יומן|user'), {'imported'});
      expect(await database.userBookKeysPending(), isFalse);
    },
  );

  test(
    'a note replaced during content loading is checked again before moving',
    () async {
      await database.insertNote(
        _note('same-id', 'ביצה', 2, 'שורה אישית ייחודית'),
      );
      final loading = Completer<void>();
      final release = Completer<void>();
      final library = _library([officialBeitza, userBeitza]);
      final running = PersonalNotesUserBookKeys(
        loadContent: (book) async {
          if (!loading.isCompleted) {
            loading.complete();
            await release.future;
          }
          return contents[personalNotesBookKey(book)]!;
        },
      ).assignPending(library);
      await loading.future;
      final replacement = _note('same-id', 'ביצה', 1, 'שנולדה ביום טוב');
      await database.insertNote(replacement);
      release.complete();
      await running;

      expect(await database.loadNotes('ביצה'), [replacement]);
      expect(await idsUnder('ביצה|user'), isEmpty);
      expect(await database.userBookKeysPending(), isTrue);
      await migration().assignPending(library);
      expect(await database.loadNotes('ביצה'), [replacement]);
      expect(await database.userBookKeysPending(), isFalse);
    },
  );

  test(
    'an import from another SQLite connection cannot be marked complete',
    () async {
      final generation = await database.userBookKeysGeneration();
      final other = sqlite3.open(
        await AppPaths.resolveNotesDbPath('personal_notes.db'),
      );
      try {
        other.execute(
          'UPDATE personal_notes_user_book_keys SET generation = generation + 1',
        );
        await database.setUserBookKeysPending(false, ifGeneration: generation);
        expect(await database.userBookKeysPending(), isTrue);
        await database.close();
        expect(await database.userBookKeysPending(), isTrue);
      } finally {
        other.close();
      }
    },
  );

  group('כותרת שתוקנה בגרשיים (#2766)', () {
    test('נשמרים מפתחות ממסד מצורף ושמות מחוץ לדלתא', () async {
      final attached = BookSource.attached('review');
      await database.insertNote(
        _note('attached', 'שות באר מרדכי|db:review', 1, 'שורה'),
      );
      await database.insertNote(_note('other', 'ספר <א>', 1, 'שורה'));
      await migration().assignPending(
        _library([
          TextBook(id: 7458, title: 'שו״ת באר מרדכי', source: attached),
          TextBook(id: 7458, title: 'שו״ת באר מרדכי'),
          TextBook(id: 80, title: 'ספר א'),
        ]),
      );
      expect(await idsUnder('שות באר מרדכי|db:review'), {'attached'});
      expect(await idsUnder('ספר <א>'), {'other'});
    });

    test('כותרת רשמית מדויקת גוברת על מפת ההסבה', () async {
      await database.insertNote(_note('exact', 'שות באר מרדכי', 1, 'שורה'));
      await migration(catalogVersion: '41').assignPending(
        _library([
          TextBook(id: 9999, title: 'שות באר מרדכי'),
          TextBook(id: 7458, title: 'שו״ת באר מרדכי'),
        ]),
      );

      expect(await idsUnder('שות באר מרדכי'), {'exact'});
      expect(await idsUnder('שו״ת באר מרדכי'), isEmpty);
    });

    test('שם קיים במסד מצורף מגן על מפתח ישן ללא מקור', () async {
      await database.insertNote(_note('legacy', 'שות באר מרדכי', 1, 'שורה'));
      await migration(catalogVersion: '40').assignPending(
        _library([
          TextBook(id: 7458, title: 'שו״ת באר מרדכי'),
          TextBook(
            id: 7458,
            title: 'שות באר מרדכי',
            source: BookSource.attached('review'),
          ),
        ]),
      );

      expect(await idsUnder('שות באר מרדכי'), {'legacy'});
      expect(await idsUnder('שו״ת באר מרדכי'), isEmpty);
    });

    test('קטלוג שנקלט לפני החלפת המסד אינו מסמן את הכותרת כטופלה', () async {
      await database.insertNote(_note('late', 'שות באר מרדכי', 1, 'שורה'));
      final service = migration(catalogVersion: '40');
      await service.assignPending(
        _library([TextBook(id: 7458, title: 'שות באר מרדכי')]),
      );
      await service.assignPending(
        _library([TextBook(id: 7458, title: 'שו״ת באר מרדכי')]),
      );

      expect(await idsUnder('שו״ת באר מרדכי'), {'late'});
    });

    test('הערות תחת הכותרת הישנה עוברות לספר המתוקן', () async {
      await database.insertNote(_note('a', 'שות באר מרדכי', 1, 'שורה'));
      await database.insertNote(_note('b', 'יומן|user', 1, 'רשימה ראשונה'));

      await migration().assignPending(
        _library([TextBook(id: 7458, title: 'שו״ת באר מרדכי'), userOnly]),
      );

      expect(await idsUnder('שו״ת באר מרדכי'), {'a'});
      expect(await idsUnder('שות באר מרדכי'), isEmpty);
      expect(await idsUnder('יומן|user'), {'b'});
      final moves = (await database.database).select(
        'SELECT from_key, to_key, note_ids FROM personal_notes_key_moves',
      );
      expect(moves.map((row) => [...row.values]), [
        ['שות באר מרדכי', 'שו״ת באר מרדכי', '["a"]'],
      ]);
    });

    test('נבדק פעם אחת לכל גרסת ספרייה', () async {
      final library = [TextBook(id: 7458, title: 'שו״ת באר מרדכי')];
      await migration(catalogVersion: 'v1').assignPending(_library(library));
      await database.insertNote(_note('late', 'שות באר מרדכי', 1, 'שורה'));

      await migration(catalogVersion: 'v1').assignPending(_library(library));
      expect(await idsUnder('שות באר מרדכי'), {'late'});

      await migration(catalogVersion: 'v2').assignPending(_library(library));
      expect(await idsUnder('שו״ת באר מרדכי'), {'late'});
    });

    test('קטלוג בלי ספרי המסד הרשמי אינו מסמן את הגרסה כטופלה', () async {
      await database.insertNote(_note('a', 'שות באר מרדכי', 1, 'שורה'));
      await migration(catalogVersion: 'v1').assignPending(_library([userOnly]));

      await migration(
        catalogVersion: 'v1',
      ).assignPending(_library([TextBook(id: 7458, title: 'שו״ת באר מרדכי')]));
      expect(await idsUnder('שו״ת באר מרדכי'), {'a'});
    });

    test('כותרת ישנה שהיא גם ספר אישי — מכריעים לפי הטקסט', () async {
      await database.insertNote(
        _note('mine', 'שות באר מרדכי', 1, 'שורה אישית'),
      );
      await database.insertNote(
        _note('official', 'שות באר מרדכי', 1, 'שורה רשמית'),
      );

      await database.insertNote(
        _note('uncertain', 'שות באר מרדכי', 1, 'שורה אחרת'),
      );

      await migration(
        content: {
          'שו״ת באר מרדכי': 'שורה רשמית',
          'שות באר מרדכי|user': 'שורה אישית',
        },
      ).assignPending(
        _library([
          TextBook(id: 7458, title: 'שו״ת באר מרדכי'),
          TextBook(id: 9, title: 'שות באר מרדכי', source: BookSource.user),
        ]),
      );

      expect(await idsUnder('שות באר מרדכי|user'), {'mine'});
      expect(await idsUnder('שו״ת באר מרדכי'), {'official'});
      expect(await idsUnder('שות באר מרדכי'), {'uncertain'});
    });

    test('ספר שעדיין בקטלוג או התאמה כפולה — ההערות נשארות', () async {
      await database.insertNote(_note('kept', 'שות חכם', 1, 'שורה'));
      await database.insertNote(_note('ambiguous', 'שות דברי חיים', 1, 'שורה'));

      await migration().assignPending(
        _library([
          TextBook(id: 4, title: 'שות חכם'),
          TextBook(id: 5, title: 'שו״ת חכם'),
          TextBook(id: 6, title: 'שו״ת דברי חיים'),
          TextBook(id: 7, title: 'שו"ת דברי חיים'),
        ]),
      );

      expect(await idsUnder('שות חכם'), {'kept'});
      expect(await idsUnder('שות דברי חיים'), {'ambiguous'});
    });
  });
}
