import 'package:equatable/equatable.dart';

/// Represents an error type with ID and Hebrew label for phone reporting
class ErrorType extends Equatable {
  final int id;
  final String hebrewLabel;

  const ErrorType({
    required this.id,
    required this.hebrewLabel,
  });

  @override
  List<Object?> get props => [id, hebrewLabel];

  /// Static list of common error types with their IDs and Hebrew labels
  static const List<ErrorType> errorTypes = [
    ErrorType(id: 1, hebrewLabel: 'שגיאת כתיב'),
    ErrorType(id: 2, hebrewLabel: 'טקסט חסר'),
    ErrorType(id: 3, hebrewLabel: 'טקסט מיותר'),
    ErrorType(id: 4, hebrewLabel: 'שגיאת עיצוב'),
    ErrorType(id: 5, hebrewLabel: 'שגיאת מקור'),
    ErrorType(id: 6, hebrewLabel: 'אחר'),
  ];
}
