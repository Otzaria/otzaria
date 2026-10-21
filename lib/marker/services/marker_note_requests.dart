import 'dart:async';

import 'package:flutter/foundation.dart';

/// כרטיס בחלונית ההערות שיכול להציג את עורך ההערה של סימון.
abstract interface class MarkerNoteEditorHost {
  /// הכרטיס בכרטיסייה הפעילה (ולא בכרטיסייה ברקע).
  bool get isActiveHost;
}

/// עריכת ההערה של סימון בחלונית ההערות. הבקשה נשמרת כאן ולא בכרטיס, כדי
/// שתשרוד את בניית החלונית מחדש כשהיא נפתחת: כרטיס אחד של הסימון, בכרטיסייה
/// הפעילה, לוקח אותה ומציג את העורך, וכרטיס שנבנה במקומו לוקח אותה שוב
/// (הטיוטה נשמרת בדרך).
class MarkerNoteRequests {
  MarkerNoteRequests._();

  /// הסימונים שההערה שלהם נערכת עכשיו בחלונית. הם נשארים בה גם כשעוד אין
  /// להם הערה, וגם כשהסינון היה מסתיר אותם.
  static final ValueNotifier<Set<String>> editing = ValueNotifier(const {});

  /// מודיע על כל שינוי, גם על בקשה חוזרת לעורך שכבר פתוח (כדי לגלול אליו)
  /// ועל כרטיס שעזב אותו (כדי שכרטיס אחר ייקח אותו).
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static final Map<String, MarkerNoteEditorHost> _owners = {};
  static final Map<String, DateTime> _openedAt = {};

  /// כמה זמן עורך שאיש אינו מציג נשאר פתוח — למשל כשהחלונית נסגרה, או
  /// כשהסימון נמחק. הטיוטה נשמרת, ונטענת בעריכה הבאה.
  static const Duration _orphanTimeout = Duration(seconds: 2);

  /// פותח את העורך של [id] בחלונית.
  static void open(String id) {
    _openedAt[id] = DateTime.now();
    if (!editing.value.contains(id)) editing.value = {...editing.value, id};
    _notify();
  }

  /// סוגר את העורך של [id], אחרי שמירה או ביטול.
  static void close(String id) {
    _owners.remove(id);
    _openedAt.remove(id);
    if (editing.value.contains(id)) {
      editing.value = {...editing.value}..remove(id);
    }
    _notify();
  }

  /// [host] מציג את העורך של [id]. כרטיס פעיל לוקח אותו גם מכרטיס בכרטיסייה
  /// ברקע (למשל אותו ספר בכרטיסייה שנייה), אבל לא מכרטיס פעיל אחר.
  static bool claim(String id, MarkerNoteEditorHost host) {
    if (!editing.value.contains(id)) return false;
    final current = _owners[id];
    if (identical(current, host)) return true;
    if (current != null && current.isActiveHost) return false;
    _owners[id] = host;
    // הבעלים הקודם מסתיר את העורך שלו.
    if (current != null) _notify();
    return true;
  }

  /// הכרטיס פורק. כרטיס שייבנה במקומו ייקח את העורך; כשאיש אינו לוקח אותו
  /// בתוך זמן קצר, הוא נסגר.
  static void release(String id, MarkerNoteEditorHost host) {
    if (!identical(_owners[id], host)) return;
    _owners.remove(id);
    _notify();
    Timer(_orphanTimeout, () {
      if (!_owners.containsKey(id) && editing.value.contains(id)) close(id);
    });
  }

  static bool isOwner(String id, MarkerNoteEditorHost host) =>
      identical(_owners[id], host);

  /// אם כרטיס בכרטיסייה הפעילה מציג את העורך של [id].
  static bool isShown(String id) => _owners[id]?.isActiveHost ?? false;

  /// מתי ביקשו לאחרונה לערוך את [id] — כדי לגלול אל הכרטיס פעם אחת לכל
  /// בקשה.
  static DateTime? openedAt(String id) => _openedAt[id];

  static void _notify() => changes.value++;

  @visibleForTesting
  static void reset() {
    _owners.clear();
    _openedAt.clear();
    editing.value = const {};
  }
}
