import 'package:equatable/equatable.dart';

/// תוצאת אימות מיקום הערות
///
/// מכילה סטטיסטיקה על תהליך אימות המיקום של הערות בספר.
class LocationVerificationResult extends Equatable {
  /// מספר ההערות שנבדקו
  final int totalNotes;

  /// מספר הערות שנשארו במיקום המקורי
  final int anchoredNotes;

  /// מספר הערות שהמיקום שלהן השתנה
  final int shiftedNotes;

  /// מספר הערות שאיבדו מיקום
  final int locationlessNotes;

  /// רשימת עדכוני מיקום שבוצעו
  final List<LocationUpdate> updates;

  const LocationVerificationResult({
    required this.totalNotes,
    required this.anchoredNotes,
    required this.shiftedNotes,
    required this.locationlessNotes,
    required this.updates,
  });

  @override
  List<Object?> get props => [
        totalNotes,
        anchoredNotes,
        shiftedNotes,
        locationlessNotes,
        updates,
      ];
}

/// עדכון מיקום של הערה בודדת
class LocationUpdate extends Equatable {
  /// מזהה ההערה
  final String noteId;

  /// מספר שורה מקורי
  final int originalLine;

  /// מספר שורה חדש (null אם לא נמצא)
  final int? newLine;

  /// ציון ההתאמה (0.0-1.0)
  final double matchScore;

  /// האם ההערה איבדה מיקום
  final bool isLocationless;

  const LocationUpdate({
    required this.noteId,
    required this.originalLine,
    this.newLine,
    required this.matchScore,
    required this.isLocationless,
  });

  @override
  List<Object?> get props => [
        noteId,
        originalLine,
        newLine,
        matchScore,
        isLocationless,
      ];
}
