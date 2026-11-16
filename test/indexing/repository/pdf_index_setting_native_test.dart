import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('כיבוי PDF מפנה את הנפח באינדקס מעורב ושומר את כל זהויות הטקסט', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    expect(await tryInitSearchEngine(), isTrue, reason: searchEngineSkipReason);
    final root = await Directory.systemTemp.createTemp('pdf-setting-native-');
    final index = await Directory('${root.path}/index').create();
    final engine = await SearchEngine.newInstance(path: index.path);
    addTearDown(() async {
      engine.dispose();
      await root.delete(recursive: true);
    });
    final pdf = PdfBook(id: 1, title: 'זהה', path: '${root.path}/a.pdf');
    final books = <Book>[
      TextBook(id: 1, title: 'זהה'),
      TextBook(id: 1, title: 'זהה', source: BookSource.user),
      TextBook(id: 1, title: 'זהה', source: BookSource.attached('fixture')),
      pdf,
    ];
    final library = Library(categories: [])..books.addAll(books);
    final docs = <DocumentInput>[
      for (final book in books)
        for (var line = 0; line < (book is PdfBook ? 1200 : 1); line++)
          DocumentInput(
            ordinal: line,
            title: book.title,
            reference: 'עמוד $line',
            topics: '/בדיקה',
            text: book is PdfBook
                ? 'ייחודי ${List.generate(100, (i) => 'מילה$lineתיבה$i').join(' ')}'
                : 'ייחודי טקסט נשמר',
            segment: BigInt.from(line + 1),
            isPdf: book is PdfBook,
            filePath: BookIdentity.indexedFilePath(book),
          ),
    ];
    await engine.addDocumentsBatch(docs: docs);
    await engine.commit();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    await provider.engine;
    provider.indexedFilePaths.addAll(books.map(BookIdentity.indexedFilePath));
    final repository = IndexingRepository(provider, indexPdfBooks: () => false);
    Future<int> bytes() async {
      var total = 0;
      await for (final file in index.list(recursive: true)) {
        if (file is File) total += await file.length();
      }
      return total;
    }

    final before = await bytes();
    final countBefore = await engine.countExact(
      query: 'ייחודי',
      facets: ['/'],
      matchNikud: false,
      matchTaamim: false,
    );
    expect(
      await repository.dropOrphanedIndexEntries(
        library,
        compact: true,
        customFolders: [],
        attachedLibraries: [],
      ),
      1,
    );
    expect(await engine.countDocumentsByFilePath(), {
      'id:1': 1,
      'uid:1': 1,
      'db:fixture:1': 1,
    });
    expect(
      await engine.countExact(
        query: 'ייחודי',
        facets: ['/'],
        matchNikud: false,
        matchTaamim: false,
      ),
      3,
    );
    expect(await repository.hasUnindexedBooks(library), false);
    final segments = await engine.getSegmentCount();
    final compacted = await bytes();
    debugPrint(
      'PDF_SETTING_DISK before=$before after=$compacted segments=$segments hitsBefore=$countBefore',
    );
    expect(compacted, lessThan(before * 0.5));
  });
}
