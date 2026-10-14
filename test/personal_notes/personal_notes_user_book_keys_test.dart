import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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

  PersonalNotesUserBookKeys migration({Map<String, String>? content}) =>
      PersonalNotesUserBookKeys(
        loadContent: (book) async =>
            (content ?? contents)[personalNotesBookKey(book)] ?? '',
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

  test('a catalog without official books is not ready and waits', () async {
    await database.insertNote(_note('a', 'יומן', 1, 'רשימה ראשונה'));

    await migration().assignPending(_library([userOnly]));

    expect(await idsUnder('יומן'), {'a'});
    expect(await database.userBookKeysPending(), isTrue);
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
}
