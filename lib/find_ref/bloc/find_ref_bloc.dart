import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/find_ref_personal_books_setting.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class FindRefBloc extends Bloc<FindRefEvent, FindRefState> {
  final FindRefRepository findRefRepository;

  /// השהיית debounce לפני שחיפוש מתחיל בפועל. כל הקלדה ב-UI שולחת
  /// `SearchRefRequested` מיידית, וה-handler ממתין כאן לפני שמתחיל ב-fetch
  /// הכבד. הקלדה חדשה תוך כדי ההמתנה תפעיל את `restartable()` ותבטל את
  /// ה-handler באותה נקודת await — כך שאף חיפוש לא יורץ מתחת ל-debounce.
  static const Duration _searchDebounce = Duration(milliseconds: 250);

  /// הנרמול שקובע אם שתי שאילתות זהות — משותף לבלוק ולמסך.
  static String normalizeQuery(String query) => normalizeForFindRefMatch(query);

  /// השאילתה המנורמלת שהניבה את התוצאות שמוצגות כרגע, יחד עם מצב הטוגל.
  /// הקלדה שאינה משנה את הנרמול (רווח, גרשיים, פיסוק) לא מריצה חיפוש מחדש
  /// ולא מהבהבת ספינר על אותן תוצאות בדיוק.
  String? _shownNormalizedQuery;
  bool? _shownIncludePersonalBooks;
  HiddenLibrarySelection? _shownVisibility;
  int _requestGeneration = 0;

  /// השאילתה שכבר קיבלה ניסיון חוזר אחרי ביטול זר. מונעת לולאת ניסיונות
  /// כשהביטול חוזר על עצמו.
  String? _retriedQuery;

  FindRefBloc({required this.findRefRepository}) : super(FindRefInitial()) {
    // restartable: כל SearchRefRequested חדש מבטל handler קודם שעדיין רץ.
    // הביטול חל בנקודת ה-await הבאה — בין אם זו השהיית ה-debounce, ובין
    // אם זו שאילתה בתוך `findRefs`. כך הקלדה חדשה מבטלת מיידית גם handlers
    // שעדיין בהמתנה וגם כאלה שכבר התחילו fetch.
    on<SearchRefRequested>(_onSearchRefRequested, transformer: restartable());
    on<ClearSearchRequested>(_onClearSearchRequested);
  }

  @override
  Future<void> close() {
    findRefRepository.dispose();
    return super.close();
  }

  Future<void> _onSearchRefRequested(
    SearchRefRequested event,
    Emitter<FindRefState> emit,
  ) async {
    final normalized = normalizeQuery(event.refText);
    final includePersonalBooks =
        event.includePersonalBooks ?? FindRefPersonalBooksSetting.load();
    final visibility = findRefRepository.respectHiddenLibrary
        ? const HiddenLibraryStore().load()
        : const HiddenLibrarySelection();
    if (event.refText.length >= 2 &&
        state is FindRefSuccess &&
        normalized == _shownNormalizedQuery &&
        includePersonalBooks == _shownIncludePersonalBooks &&
        visibility == _shownVisibility) {
      return;
    }

    final requestGeneration = ++_requestGeneration;
    findRefRepository.cancelPendingSearch();
    if (event.refText.length < 2) {
      _shownNormalizedQuery = null;
      _shownIncludePersonalBooks = null;
      _shownVisibility = null;
      _retriedQuery = null;
      emit(const FindRefSuccess([]));
      return;
    }

    // debounce: ממתינים לפני שמתחילים ב-fetch. אם המשתמש מקליד שוב לפני
    // שהדיליי מסתיים — restartable יבטל את ה-handler הזה כאן בלי שיתחיל
    // לטעון נתונים.
    await Future.delayed(_searchDebounce);
    if (emit.isDone || requestGeneration != _requestGeneration) return;

    emit(FindRefLoading());
    try {
      final List<DbReferenceResult> refs = await findRefRepository.findRefs(
        event.refText,
        includePersonalBooks: includePersonalBooks,
      );
      // emit.isDone יהיה true אם ה-handler בוטל ע"י restartable
      // (event חדש הגיע באמצע ה-fetch). במצב כזה לא נכתוב את התוצאות
      // המיושנות.
      if (emit.isDone || requestGeneration != _requestGeneration) return;
      _shownNormalizedQuery = normalized;
      _shownIncludePersonalBooks = includePersonalBooks;
      _shownVisibility = visibility;
      _retriedQuery = null;
      emit(
        FindRefSuccess(
          refs,
          query: event.refText,
          includePersonalBooks: includePersonalBooks,
        ),
      );
    } on ReferenceLibraryNotReadyException {
      if (emit.isDone || requestGeneration != _requestGeneration) return;
      emit(const FindRefNotReady());
    } on ReferenceLibraryMissingException {
      if (emit.isDone || requestGeneration != _requestGeneration) return;
      emit(const FindRefLibraryMissing());
    } on FindRefQueryCancelled {
      // הקלדה חדשה זרקה את השאילתה מתור ה-worker. ה-handler של אותה הקלדה
      // יעדכן את המצב — אין להציג כאן שגיאה ואין לכתוב תוצאות חלקיות.
      if (emit.isDone || requestGeneration != _requestGeneration) return;
      // אף בקשה חדשה לא באה אחרינו, ולכן הביטול הגיע ממקור אחר (מרוץ epoch
      // מול ה-worker). בלי ניסיון חוזר ה-state נשאר Loading לנצח.
      if (_retriedQuery != event.refText) {
        _retriedQuery = event.refText;
        add(
          SearchRefRequested(
            event.refText,
            includePersonalBooks: includePersonalBooks,
          ),
        );
        return;
      }
      emit(const FindRefError(FindRefErrorKind.cancelled));
    } catch (e, stackTrace) {
      if (emit.isDone || requestGeneration != _requestGeneration) return;
      debugPrint('[FindRef] search failed: $e\n$stackTrace');
      emit(const FindRefError(FindRefErrorKind.failed));
    }
  }

  void _onClearSearchRequested(
    ClearSearchRequested event,
    Emitter<FindRefState> emit,
  ) {
    _requestGeneration++;
    findRefRepository.cancelPendingSearch();
    _shownNormalizedQuery = null;
    _shownIncludePersonalBooks = null;
    _shownVisibility = null;
    _retriedQuery = null;
    emit(FindRefInitial());
  }
}
