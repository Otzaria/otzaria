import 'package:equatable/equatable.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';

abstract class FindRefState extends Equatable {
  const FindRefState();

  @override
  List<Object> get props => [];
}

class FindRefInitial extends FindRefState {}

class FindRefLoading extends FindRefState {}

class FindRefSuccess extends FindRefState {
  final List<DbReferenceResult> refs;

  /// השאילתה שהניבה את [refs] — לא בהכרח מה שמוקלד כרגע בשדה, שכן
  /// המשתמש ממשיך להקליד בזמן שהתוצאות הקודמות עדיין מוצגות.
  final String query;

  /// מצב מתג הספרים האישיים שבו רץ [query].
  final bool includePersonalBooks;

  const FindRefSuccess(
    this.refs, {
    this.query = '',
    this.includePersonalBooks = false,
  });

  @override
  List<Object> get props => [refs, query, includePersonalBooks];
}

/// מטמון הספרים של האיתור לא נטען, ולכן לא היה במה לחפש. נבדל מ-
/// [FindRefSuccess] ריק כדי שהמסך לא יציג "לא נמצא ספר" על ספרייה שרק
/// עוד לא מוכנה.
class FindRefNotReady extends FindRefState {
  const FindRefNotReady();
}

/// אין ספרייה מותקנת — בניגוד ל-[FindRefNotReady], ניסיון חוזר לא יעזור.
class FindRefLibraryMissing extends FindRefState {
  const FindRefLibraryMissing();
}

enum FindRefErrorKind { cancelled, failed }

/// הטקסט המוצג נקבע במסך לפי [kind]; פרטי החריגה נרשמים ללוג בלבד.
class FindRefError extends FindRefState {
  final FindRefErrorKind kind;
  const FindRefError(this.kind);

  @override
  List<Object> get props => [kind];
}
