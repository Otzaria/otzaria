import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class FindRefBloc extends Bloc<FindRefEvent, FindRefState> {
  final FindRefRepository findRefRepository;

  /// השהיית debounce לפני שחיפוש מתחיל בפועל. כל הקלדה ב-UI שולחת
  /// `SearchRefRequested` מיידית, וה-handler ממתין כאן לפני שמתחיל ב-fetch
  /// הכבד. הקלדה חדשה תוך כדי ההמתנה תפעיל את `restartable()` ותבטל את
  /// ה-handler באותה נקודת await — כך שאף חיפוש לא יורץ מתחת ל-debounce.
  static const Duration _searchDebounce = Duration(milliseconds: 250);

  /// השאילתה המנורמלת שהניבה את התוצאות שמוצגות כרגע, יחד עם מצב הטוגל.
  /// הקלדה שאינה משנה את הנרמול (רווח, גרשיים, פיסוק) לא מריצה חיפוש מחדש
  /// ולא מהבהבת ספינר על אותן תוצאות בדיוק.
  String? _shownNormalizedQuery;
  bool? _shownIncludePersonalBooks;

  FindRefBloc({required this.findRefRepository}) : super(FindRefInitial()) {
    // restartable: כל SearchRefRequested חדש מבטל handler קודם שעדיין רץ.
    // הביטול חל בנקודת ה-await הבאה — בין אם זו השהיית ה-debounce, ובין
    // אם זו שאילתה בתוך `findRefs`. כך הקלדה חדשה מבטלת מיידית גם handlers
    // שעדיין בהמתנה וגם כאלה שכבר התחילו fetch.
    on<SearchRefRequested>(_onSearchRefRequested, transformer: restartable());
    on<ClearSearchRequested>(_onClearSearchRequested);
    on<OpenBookRequested>(_onOpenBookRequested);
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
    if (event.refText.length < 2) {
      _shownNormalizedQuery = null;
      _shownIncludePersonalBooks = null;
      emit(const FindRefSuccess([]));
      return;
    }

    final normalized = normalizeForFindRefMatch(event.refText);
    // התוצאות המוצגות כבר שייכות לשאילתה הזו. חובה לבדוק גם את המצב: אם
    // ה-handler הקודם נהרג באמצע fetch, על המסך ספינר ולא תוצאות.
    if (state is FindRefSuccess &&
        normalized == _shownNormalizedQuery &&
        event.includePersonalBooks == _shownIncludePersonalBooks) {
      return;
    }
    // debounce: ממתינים לפני שמתחילים ב-fetch. אם המשתמש מקליד שוב לפני
    // שהדיליי מסתיים — restartable יבטל את ה-handler הזה כאן בלי שיתחיל
    // לטעון נתונים.
    await Future.delayed(_searchDebounce);
    if (emit.isDone) return;

    emit(FindRefLoading());
    try {
      final List<DbReferenceResult> refs = await findRefRepository.findRefs(
        event.refText,
        includePersonalBooks: event.includePersonalBooks,
      );
      // emit.isDone יהיה true אם ה-handler בוטל ע"י restartable
      // (event חדש הגיע באמצע ה-fetch). במצב כזה לא נכתוב את התוצאות
      // המיושנות.
      if (emit.isDone) return;
      _shownNormalizedQuery = normalized;
      _shownIncludePersonalBooks = event.includePersonalBooks;
      emit(FindRefSuccess(refs, query: event.refText));
    } on ReferenceLibraryNotReadyException {
      if (emit.isDone) return;
      emit(const FindRefNotReady());
    } on FindRefQueryCancelled {
      // הקלדה חדשה זרקה את השאילתה מתור ה-worker. ה-handler של אותה הקלדה
      // יעדכן את המצב — אין להציג כאן שגיאה ואין לכתוב תוצאות חלקיות.
      return;
    } catch (e) {
      if (emit.isDone) return;
      emit(FindRefError(e.toString()));
    }
  }

  void _onClearSearchRequested(
    ClearSearchRequested event,
    Emitter<FindRefState> emit,
  ) {
    _shownNormalizedQuery = null;
    _shownIncludePersonalBooks = null;
    emit(FindRefInitial());
  }

  void _onOpenBookRequested(
    OpenBookRequested event,
    Emitter<FindRefState> emit,
  ) {
    final book = event.book;
    final index = event.index;
    emit(
      FindRefBookOpening(book: book, index: index),
    ); // Emit BookOpening state
  }
}

class FindRefBookOpening extends FindRefState {
  // Define BookOpening state
  final Book book;
  final int index;

  const FindRefBookOpening({required this.book, required this.index});

  @override
  List<Object> get props => [book, index];
}
