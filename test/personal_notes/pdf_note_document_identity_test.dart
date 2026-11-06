import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/personal_notes/utils/personal_note_source_link.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_filter.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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

PersonalNote _note(PdfBook book) => PersonalNote(
  id: 'note',
  bookId: personalNotesBookKey(book),
  lineNumber: 2,
  pdfAnchor: PdfNoteAnchor(
    pageNumber: 2,
    x: .35,
    y: .65,
    documentId: pdfPersonalNoteDocumentId(book),
  ),
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: 'תוכן',
  contentPlain: 'תוכן',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppPaths.debugOverrideDataRootPath(null);
    return Settings.init(cacheProvider: MemoryCacheProvider());
  });
  tearDown(() => AppPaths.debugOverrideDataRootPath(null));

  for (final source in [BookSource.official, BookSource.user]) {
    test(
      'PDF notes survive moving the library and JSON restore (${source.wireKey})',
      () async {
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          r'C:\old\library',
        );
        final old = PdfBook(
          id: 42,
          title: 'ספר',
          path: r'C:\old\library\nested\ספר.pdf',
          source: source,
        );
        final saved = _note(old);
        final restored = PersonalNote.fromJson(
          jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
        );
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          '/new/library',
        );
        final moved = PdfBook(
          id: 42,
          title: old.title,
          path: '/new/library/nested/ספר.pdf',
          source: source,
        );
        expect(pdfPersonalNoteDocumentId(moved), saved.pdfAnchor!.documentId);
        expect(
          personalNoteSourceBook(_library([moved]), restored),
          same(moved),
        );
        expect(
          filterPersonalNotes(
            locatedNotes: [restored],
            missingNotes: [],
            searchQuery: '',
            showOnlyVisible: false,
            visibleLineIndices: [],
            isPdf: true,
            pdfDocumentId: pdfPersonalNoteDocumentId(moved),
          ).locatedNotes,
          [restored],
        );
      },
    );
  }

  for (final source in [BookSource.official, BookSource.user]) {
    test(
      'full relative subdirectories distinguish PDFs with a borrowed id (${source.wireKey})',
      () async {
        await Settings.setValue(SettingsRepository.keyLibraryPath, '/library');
        final first = PdfBook(
          id: 1,
          title: 'ספר',
          path: '/library/one/ספר.pdf',
          source: source,
        );
        final second = PdfBook(
          id: 1,
          title: 'ספר',
          path: '/library/two/ספר.pdf',
          source: source,
        );
        expect(
          pdfPersonalNoteDocumentId(first),
          isNot(pdfPersonalNoteDocumentId(second)),
        );
        expect(
          personalNoteSourceBook(_library([first, second]), _note(first)),
          same(first),
        );
        expect(
          pdfPersonalNoteAnchorMatchesBook(_note(first).pdfAnchor!, second),
          isFalse,
        );
      },
    );
  }

  test(
    'outside-library paths never alias a managed relative document',
    () async {
      await Settings.setValue(SettingsRepository.keyLibraryPath, '/library');
      final managed = PdfBook(title: 'ספר', path: '/library/one/ספר.pdf');
      final outside = PdfBook(title: 'ספר', path: '/one/ספר.pdf');
      final prefixSibling = PdfBook(
        title: 'ספר',
        path: '/library-other/one/ספר.pdf',
      );
      expect(
        pdfPersonalNoteDocumentId(managed),
        isNot(pdfPersonalNoteDocumentId(outside)),
      );
      expect(
        pdfPersonalNoteDocumentId(managed),
        isNot(pdfPersonalNoteDocumentId(prefixSibling)),
      );
    },
  );

  test(
    'source-scoped ids separate same-title personal PDFs and preserve external identities',
    () {
      final first = PdfBook(
        id: 1,
        title: 'ספר',
        path: '/one.pdf',
        source: BookSource.user,
      );
      final second = PdfBook(
        id: 2,
        title: 'ספר',
        path: '/two.pdf',
        source: BookSource.user,
      );
      expect(
        pdfPersonalNoteDocumentId(first),
        isNot(pdfPersonalNoteDocumentId(second)),
      );
      final external = PdfBook(
        id: 1,
        title: 'ספר',
        path: '/one.pdf',
        source: BookSource.user,
        externalLibraryId: 'external:7',
      );
      final moved = PdfBook(
        id: 2,
        title: 'ספר',
        path: '/two.pdf',
        source: BookSource.user,
        externalLibraryId: 'external:7',
      );
      expect(
        pdfPersonalNoteDocumentId(external),
        pdfPersonalNoteDocumentId(moved),
      );
      expect(
        pdfPersonalNoteDocumentId(external),
        isNot(pdfPersonalNoteDocumentId(first)),
      );
    },
  );
  test(
    'Windows forward-slash drive and UNC roots keep portable relative identity',
    () async {
      for (final root in ['C:/library', r'\\server\share\library']) {
        await Settings.setValue(SettingsRepository.keyLibraryPath, root);
        final original = PdfBook(title: 'ספר', path: '$root/one/ספר.pdf');
        final identity = pdfPersonalNoteDocumentId(original);
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          '/new/library',
        );
        expect(
          identity,
          pdfPersonalNoteDocumentId(
            PdfBook(title: 'ספר', path: '/new/library/one/ספר.pdf'),
          ),
        );
      }
    },
  );

  test(
    'legacy current-path identities retain navigation, links, and filtering without guessing moved paths',
    () async {
      await Settings.setValue(SettingsRepository.keyLibraryPath, '/library');
      for (final source in [BookSource.official, BookSource.user]) {
        final book = PdfBook(
          id: 42,
          title: 'ספר',
          path: '/library/one/ספר.pdf',
          source: source,
        );
        final legacy = '${source.wireKey}|${Uri.encodeComponent(book.path)}';
        final note = _note(book).copyWith(
          pdfAnchor: PdfNoteAnchor(
            pageNumber: 2,
            x: .35,
            y: .65,
            documentId: legacy,
          ),
        );
        expect(personalNoteSourceBook(_library([book]), note), same(book));
        expect(pdfPersonalNoteAnchorMatchesBook(note.pdfAnchor!, book), isTrue);
        expect(
          personalNoteSourceLink(book, note, pdfLinkCandidates: [book]),
          isNotNull,
        );
        expect(
          filterPersonalNotes(
            locatedNotes: [note],
            missingNotes: [],
            searchQuery: '',
            showOnlyVisible: false,
            visibleLineIndices: [],
            isPdf: true,
            pdfDocumentId: pdfPersonalNoteDocumentId(book),
            pdfDocumentIds: pdfPersonalNoteDocumentIds(book),
          ).locatedNotes,
          [note],
        );
        final replacement = PdfBook(
          id: 42,
          title: 'ספר',
          path: '/library/two/ספר.pdf',
          source: source,
        );
        expect(personalNoteSourceBook(_library([replacement]), note), isNull);
      }
    },
  );
  test(
    'POSIX roots remain case sensitive and preserve literal backslashes',
    () async {
      await Settings.setValue(SettingsRepository.keyLibraryPath, '/library');
      final inside = PdfBook(title: 'ספר', path: '/library/one/ספר.pdf');
      final outside = PdfBook(title: 'ספר', path: '/Library/one/ספר.pdf');
      expect(pdfPersonalNoteDocumentId(inside), startsWith('o|v2:library:'));
      expect(
        pdfPersonalNoteDocumentId(outside),
        isNot(startsWith('o|v2:library:')),
      );
      final slash = PdfBook(title: 'ספר', path: '/library/one/two/ספר.pdf');
      final backslash = PdfBook(
        title: 'ספר',
        path: r'/library/one\two/ספר.pdf',
      );
      expect(
        pdfPersonalNoteDocumentId(backslash),
        'o|v2:library:${Uri.encodeComponent(r'one\two/ספר.pdf')}',
      );
      expect(
        pdfPersonalNoteDocumentId(backslash),
        isNot(pdfPersonalNoteDocumentId(slash)),
      );
    },
  );
  test(
    'imported personal PDF keeps identity when the data root moves across platforms',
    () async {
      AppPaths.debugOverrideDataRootPath(r'C:\profile\otzaria');
      final old = PdfBook(
        id: 42,
        title: 'ספר',
        path: r'C:\profile\otzaria\הספרים שלי\one\ספר.pdf',
        source: BookSource.user,
      );
      final saved = PersonalNote.fromJson(
        jsonDecode(jsonEncode(_note(old).toJson())) as Map<String, dynamic>,
      );
      expect(saved.pdfAnchor!.documentId, startsWith('u|v2:data:'));
      AppPaths.debugOverrideDataRootPath('/new/profile/otzaria');
      final moved = PdfBook(
        id: 42,
        title: 'ספר',
        path: '/new/profile/otzaria/הספרים שלי/one/ספר.pdf',
        source: BookSource.user,
      );
      final other = PdfBook(
        id: 42,
        title: 'ספר',
        path: '/new/profile/otzaria/הספרים שלי/two/ספר.pdf',
        source: BookSource.user,
      );
      expect(pdfPersonalNoteDocumentId(moved), saved.pdfAnchor!.documentId);
      expect(
        personalNoteSourceBook(_library([moved, other]), saved),
        same(moved),
      );
      expect(
        pdfPersonalNoteAnchorMatchesBook(saved.pdfAnchor!, other),
        isFalse,
      );
    },
  );

  test(
    'nested roots retain the more specific namespace when either root is relocated',
    () async {
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        '/data/library',
      );
      AppPaths.debugOverrideDataRootPath('/data');
      final libraryBook = PdfBook(
        title: 'ספר',
        path: '/data/library/one/ספר.pdf',
      );
      final libraryId = pdfPersonalNoteDocumentId(libraryBook);
      expect(libraryId, startsWith('o|v2:library:'));
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        '/elsewhere/library',
      );
      expect(
        pdfPersonalNoteDocumentId(
          PdfBook(title: 'ספר', path: '/elsewhere/library/one/ספר.pdf'),
        ),
        libraryId,
      );
      await Settings.setValue(SettingsRepository.keyLibraryPath, '/library');
      AppPaths.debugOverrideDataRootPath('/library/data');
      final dataBook = PdfBook(title: 'ספר', path: '/library/data/one/ספר.pdf');
      final dataId = pdfPersonalNoteDocumentId(dataBook);
      expect(dataId, startsWith('o|v2:data:'));
      AppPaths.debugOverrideDataRootPath('/elsewhere/data');
      expect(
        pdfPersonalNoteDocumentId(
          PdfBook(title: 'ספר', path: '/elsewhere/data/one/ספר.pdf'),
        ),
        dataId,
      );
    },
  );
}
