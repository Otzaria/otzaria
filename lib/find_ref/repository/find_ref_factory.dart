import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/models/book_source.dart';

/// בונה [FindRefRepository] מחווט ל-[FindRefDbIsolate] לכל שאילתות `seforim.db`
/// הכבדות (TOC/AltToc/מפרשים/דור), כך שלא יקפיאו את ה-UI.
/// משותף בין דיאלוג "איתור מקורות" לבין פתיחת ספר במיקום מתוך תוספים.
FindRefRepository buildFindRefRepository({bool respectHiddenLibrary = true}) {
  final scope = FindRefDbIsolate.allocateSearchScope();
  late final FindRefRepository repository;

  Future<({FindRefDbIsolate worker, int epoch})> searchWorker() async {
    final epoch = repository.currentSearchGeneration;
    final worker = await FindRefDbIsolate.instance();
    return (worker: worker, epoch: epoch);
  }

  repository = FindRefRepository(
    dataRepository: DataRepository.instance,
    respectHiddenLibrary: respectHiddenLibrary,
    getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.getTocEntries(
        bookId,
        bookTitle,
        queryTokens: queryTokens,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    getAltTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.getAltTocEntries(
        bookId,
        bookTitle,
        queryTokens: queryTokens,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    getTocForBooks: (books) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.getTocForBooks(
        books,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    getAllAltTocFlatEntries: () async =>
        (await FindRefDbIsolate.instance()).getAllAltTocFlat(),
    searchAltTocFlatEntries: (queryTokens, {maxRefTokens}) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.searchAltTocFlat(
        queryTokens,
        maxRefTokens: maxRefTokens,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    prewarmAltTocFlatEntries: () async =>
        (await FindRefDbIsolate.instance()).prewarmAltTocFlat(),
    getAltStructureBookIds: () async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.getAltStructureBookIds(
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    fetchCommentatorRows: (ref) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.getCommentatorRows(
        bookId: ref.bookId,
        bookTitle: ref.title,
        sourceLineId: ref.sourceLineId,
        startLineIndex: ref.segment.toInt(),
        level: ref.tocLevel,
        isAltToc: ref.isAltToc,
        isSourceLine: ref.isSourceLine,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    resolveLineRefs: (bookIds, refKey) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.resolveLineRefs(
        bookIds,
        refKey,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    resolvePartialLineRefs: (bookIds, partialKey) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.resolvePartialLineRefs(
        bookIds,
        partialKey,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    resolveDibburim: (bookIds, prefix, {containsBookIds = const []}) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.resolveDibburim(
        bookIds,
        prefix,
        containsBookIds: containsBookIds,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    cachedEraOrder: (bookId) => GenerationCache.instance.isLoaded
        ? GenerationCache.instance.getOrderForBook(bookId, BookSource.official)
        : null,
    getBookEras: (bookTitles) async {
      final request = await searchWorker();
      repository.throwIfSearchGenerationCancelled(request.epoch);
      return request.worker.getBookEras(
        bookTitles,
        searchScope: scope,
        searchEpoch: request.epoch,
      );
    },
    beginSearchEpoch: () => FindRefDbIsolate.cancelSearchScopeIfRunning(
      scope,
      repository.activeSearchGeneration,
    ),
    releaseSearchScope: () => FindRefDbIsolate.releaseSearchScope(scope),
  );
  return repository;
}
