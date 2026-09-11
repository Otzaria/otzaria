import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

/// בונה [FindRefRepository] מחווט ל-[FindRefDbIsolate] לכל שאילתות `seforim.db`
/// הכבדות (TOC/AltToc/מפרשים/דור), כך שלא יקפיאו את ה-UI.
/// משותף בין דיאלוג "איתור מקורות" לבין פתיחת ספר במיקום מתוך תוספים.
FindRefRepository buildFindRefRepository() {
  return FindRefRepository(
    dataRepository: DataRepository.instance,
    getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        (await FindRefDbIsolate.instance()).getTocEntries(
          bookId,
          bookTitle,
          queryTokens: queryTokens,
        ),
    getAltTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        (await FindRefDbIsolate.instance()).getAltTocEntries(
          bookId,
          bookTitle,
          queryTokens: queryTokens,
        ),
    getAllAltTocFlatEntries: () async =>
        (await FindRefDbIsolate.instance()).getAllAltTocFlat(),
    searchAltTocFlatEntries: (queryTokens, {maxRefTokens}) async =>
        (await FindRefDbIsolate.instance()).searchAltTocFlat(
          queryTokens,
          maxRefTokens: maxRefTokens,
        ),
    prewarmAltTocFlatEntries: () async =>
        (await FindRefDbIsolate.instance()).prewarmAltTocFlat(),
    getAltStructureBookIds: () async =>
        (await FindRefDbIsolate.instance()).getAltStructureBookIds(),
    fetchCommentatorRows: (ref) async =>
        (await FindRefDbIsolate.instance()).getCommentatorRows(
          bookId: ref.bookId,
          bookTitle: ref.title,
          sourceLineId: ref.sourceLineId,
          startLineIndex: ref.segment.toInt(),
          level: ref.tocLevel,
          isAltToc: ref.isAltToc,
          isSourceLine: ref.isSourceLine,
        ),
    resolveLineRefs: (bookIds, refKey) async =>
        (await FindRefDbIsolate.instance()).resolveLineRefs(bookIds, refKey),
    getBookEra: (bookTitle) async =>
        (await FindRefDbIsolate.instance()).getBookEra(bookTitle),
    beginSearchEpoch: FindRefDbIsolate.beginSearchEpochIfRunning,
  );
}
