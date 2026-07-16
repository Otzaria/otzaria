class FoundationalBookClassifier {
  FoundationalBookClassifier._();

  static int? classify(String? categoryPath, String title) {
    if (categoryPath == null || categoryPath.isEmpty) return null;

    final parts = _splitCategoryPath(categoryPath);
    if (parts.isEmpty) return null;

    const commentaryMarkers = {
      'ראשונים',
      'אחרונים',
      'מחברי זמננו',
      'מפרשים',
      'תרגומים',
      'דרשות ודרושים',
      'ספרות עזר',
      'מסכתות קטנות',
      'מערכות ועניינים',
      'מפרשים על המסכתות הקטנות',
    };
    for (final part in parts) {
      if (commentaryMarkers.contains(part)) return null;
    }

    final root = parts[0];
    final second = parts.length >= 2 ? parts[1] : null;

    if (root == 'תנ"ך' &&
        parts.length == 2 &&
        (second == 'תורה' || second == 'נביאים' || second == 'כתובים')) {
      return 1;
    }

    if (root == 'משנה' &&
        parts.length == 2 &&
        (second?.startsWith('סדר ') ?? false)) {
      return 2;
    }

    if (root == 'תלמוד בבלי' &&
        parts.length == 2 &&
        (second?.startsWith('סדר ') ?? false)) {
      return 3;
    }

    if (root == 'תלמוד ירושלמי' &&
        parts.length == 2 &&
        (second?.startsWith('סדר ') ?? false)) {
      return 4;
    }

    if (root == 'מדרש' &&
        second == 'הלכה' &&
        parts.length == 2 &&
        !_titleSuggestsCommentary(title)) {
      return 5;
    }

    if (root == 'מדרש' &&
        second == 'אגדה' &&
        parts.length == 2 &&
        !_titleSuggestsCommentary(title)) {
      return 6;
    }

    if (root == 'קבלה' &&
        second == 'זהר' &&
        parts.length == 2 &&
        _isPrimaryZoharTitle(title)) {
      return 7;
    }

    if (root == 'הלכה' &&
        second == 'משנה תורה' &&
        parts.length == 3 &&
        (parts[2].startsWith('ספר ') || parts[2] == 'הקדמה')) {
      return 8;
    }

    if (root == 'הלכה' && second == 'טור' && parts.length == 2) return 9;

    if (root == 'הלכה' && second == 'שולחן ערוך' && parts.length == 2) {
      return 10;
    }

    return null;
  }

  /// נתיב קטגוריה מגיע בשני פורמטים: "תנ\"ך, תורה" (join בפסיק —
  /// _categoryPathForBook / ReferenceBooksCache) או "/תנ\"ך/תורה"
  /// (Category.path עם slash). פיצול לפי הפורמט בפועל, אחרת הסיווג
  /// נכשל בשקט ומחזיר null לספרי יסוד אמיתיים.
  static List<String> _splitCategoryPath(String categoryPath) {
    final normalized = categoryPath.trim();
    final parts = normalized.contains(', ')
        ? normalized.split(', ')
        : normalized.split('/');
    return [
      for (final part in parts)
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static bool _titleSuggestsCommentary(String title) {
    return title.contains(' על ') ||
        title.startsWith('פירוש ') ||
        title.startsWith('הערות ') ||
        title.startsWith('ביאור ');
  }

  static bool _isPrimaryZoharTitle(String title) {
    const primary = {
      'ספר הזהר',
      'זוהר חדש',
      'תקוני הזהר',
      'אדרא רבא',
      'אדרא זוטא',
      'ספרא דצניעותא',
    };
    return primary.contains(title);
  }
}
