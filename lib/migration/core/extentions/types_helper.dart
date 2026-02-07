// פונקציית עזר גלובלית להמרת dynamic ל-bool
// מניחה שערכים מסוג int הם 0 (false) או 1 (true)
bool safeBoolFromJson(dynamic jsonValue, [bool defaultValue = false]) {
  if (jsonValue == null) {
    return defaultValue;
  }

  // מטפל במקרה שבו ה-JSON כבר מגיע כ-bool
  if (jsonValue is bool) {
    return jsonValue;
  }

  // מטפל במקרה שבו ה-JSON מגיע כ-int (0 או 1)
  if (jsonValue is int) {
    return jsonValue != 0;
  }

  // טיפול כללי או החזרת ערך ברירת מחדל
  return defaultValue;
}

// ניתן להוסיף כאן פונקציות עזר נוספות (למשל, המרת String בטוחה ל-int)
