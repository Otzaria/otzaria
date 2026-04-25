/// מצבי התצוגה האפשריים של ניקוד ופיסוק במסך הספר.
enum TextDisplayVisibilityPreset {
  /// הצגת כל סימני הטקסט.
  showAll,

  /// הסרת ניקוד בלבד.
  removeNikud,

  /// הסרת פיסוק בלבד.
  removePunctuation,

  /// הסרת ניקוד ופיסוק יחד.
  removeAll,
}

/// מחזיר את מצב התצוגה המתאים לפי ערכי ההסתרה הפעילים.
TextDisplayVisibilityPreset resolveTextDisplayVisibilityPreset({
  required bool removeNikud,
  required bool removePunctuation,
}) {
  if (removeNikud && removePunctuation) {
    return TextDisplayVisibilityPreset.removeAll;
  }
  if (removeNikud) {
    return TextDisplayVisibilityPreset.removeNikud;
  }
  if (removePunctuation) {
    return TextDisplayVisibilityPreset.removePunctuation;
  }
  return TextDisplayVisibilityPreset.showAll;
}

/// מחזיר את ערכי ההסתרה שיש להחיל עבור מצב התצוגה שנבחר.
({
  bool removeNikud,
  bool removePunctuation,
}) applyTextDisplayVisibilityPreset(
  TextDisplayVisibilityPreset preset,
) {
  return switch (preset) {
    TextDisplayVisibilityPreset.showAll => (
        removeNikud: false,
        removePunctuation: false,
      ),
    TextDisplayVisibilityPreset.removeNikud => (
        removeNikud: true,
        removePunctuation: false,
      ),
    TextDisplayVisibilityPreset.removePunctuation => (
        removeNikud: false,
        removePunctuation: true,
      ),
    TextDisplayVisibilityPreset.removeAll => (
        removeNikud: true,
        removePunctuation: true,
      ),
  };
}
