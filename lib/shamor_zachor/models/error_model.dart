/// Enumeration of possible error types in Shamor Zachor
enum ShamorZachorErrorType {
  /// Asset file not found
  missingAsset,

  /// JSON parsing error
  parseError,

  /// SharedPreferences not available
  storageUnavailable,

  /// Network error (future use)
  networkError,

  /// Invalid data format
  invalidData,

  /// Permission denied
  permissionDenied,

  /// Unknown error
  unknown,
}

/// Represents an error that occurred in Shamor Zachor
class ShamorZachorError {
  final ShamorZachorErrorType type;
  final String message;
  final String? details;
  final Object? originalError;
  final StackTrace? stackTrace;

  const ShamorZachorError({
    required this.type,
    required this.message,
    this.details,
    this.originalError,
    this.stackTrace,
  });

  /// Create an error from an exception
  factory ShamorZachorError.fromException(
    Object exception, {
    StackTrace? stackTrace,
    ShamorZachorErrorType? type,
    String? customMessage,
  }) {
    final errorType = type ?? _inferErrorType(exception);
    final message = customMessage ?? _getDefaultMessage(errorType);

    return ShamorZachorError(
      type: errorType,
      message: message,
      details: exception.toString(),
      originalError: exception,
      stackTrace: stackTrace,
    );
  }

  /// Get user-friendly Hebrew message
  String get userFriendlyMessage {
    switch (type) {
      case ShamorZachorErrorType.missingAsset:
        return 'קובץ נתונים חסר. אנא ודא שהאפליקציה מותקנת כראוי.';
      case ShamorZachorErrorType.parseError:
        return 'שגיאה בקריאת נתוני הספרים. ייתכן שהקבצים פגומים.';
      case ShamorZachorErrorType.storageUnavailable:
        return 'לא ניתן לשמור את ההתקדמות. בדוק את הרשאות האפליקציה.';
      case ShamorZachorErrorType.networkError:
        return 'בעיית חיבור לאינטרנט. בדוק את החיבור שלך.';
      case ShamorZachorErrorType.invalidData:
        return 'נתונים לא תקינים. אנא נסה שוב.';
      case ShamorZachorErrorType.permissionDenied:
        return 'אין הרשאה לבצע פעולה זו.';
      case ShamorZachorErrorType.unknown:
        return 'אירעה שגיאה לא צפויה. אנא נסה שוב.';
    }
  }

  /// Check if this error is recoverable
  bool get isRecoverable {
    switch (type) {
      case ShamorZachorErrorType.networkError:
      case ShamorZachorErrorType.storageUnavailable:
        return true;
      case ShamorZachorErrorType.missingAsset:
      case ShamorZachorErrorType.parseError:
      case ShamorZachorErrorType.invalidData:
      case ShamorZachorErrorType.permissionDenied:
      case ShamorZachorErrorType.unknown:
        return false;
    }
  }

  /// Get suggested action for the user
  String? get suggestedAction {
    switch (type) {
      case ShamorZachorErrorType.networkError:
        return 'בדוק את חיבור האינטרנט ונסה שוב';
      case ShamorZachorErrorType.storageUnavailable:
        return 'בדוק את הרשאות האפליקציה בהגדרות המכשיר';
      case ShamorZachorErrorType.missingAsset:
        return 'התקן מחדש את האפליקציה';
      case ShamorZachorErrorType.parseError:
      case ShamorZachorErrorType.invalidData:
        return 'נסה לרענן את הנתונים או התקן מחדש';
      case ShamorZachorErrorType.permissionDenied:
        return 'בדוק את הרשאות האפליקציה';
      case ShamorZachorErrorType.unknown:
        return 'נסה שוב או פנה לתמיכה';
    }
  }

  @override
  String toString() {
    return 'ShamorZachorError(type: $type, message: $message, details: $details)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShamorZachorError &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          message == other.message &&
          details == other.details;

  @override
  int get hashCode => type.hashCode ^ message.hashCode ^ details.hashCode;
}

/// Infer error type from exception
ShamorZachorErrorType _inferErrorType(Object exception) {
  final exceptionString = exception.toString().toLowerCase();

  if (exceptionString.contains('asset') || exceptionString.contains('file')) {
    return ShamorZachorErrorType.missingAsset;
  }
  if (exceptionString.contains('json') || exceptionString.contains('format')) {
    return ShamorZachorErrorType.parseError;
  }
  if (exceptionString.contains('storage') ||
      exceptionString.contains('preferences')) {
    return ShamorZachorErrorType.storageUnavailable;
  }
  if (exceptionString.contains('network') ||
      exceptionString.contains('connection')) {
    return ShamorZachorErrorType.networkError;
  }
  if (exceptionString.contains('permission')) {
    return ShamorZachorErrorType.permissionDenied;
  }

  return ShamorZachorErrorType.unknown;
}

/// Get default message for error type
String _getDefaultMessage(ShamorZachorErrorType type) {
  switch (type) {
    case ShamorZachorErrorType.missingAsset:
      return 'Missing asset file';
    case ShamorZachorErrorType.parseError:
      return 'Data parsing error';
    case ShamorZachorErrorType.storageUnavailable:
      return 'Storage unavailable';
    case ShamorZachorErrorType.networkError:
      return 'Network error';
    case ShamorZachorErrorType.invalidData:
      return 'Invalid data';
    case ShamorZachorErrorType.permissionDenied:
      return 'Permission denied';
    case ShamorZachorErrorType.unknown:
      return 'Unknown error';
  }
}
