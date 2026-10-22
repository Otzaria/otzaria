import 'package:flutter/widgets.dart';

/// טקסט חיפוש שנשלח לכלי מובנה, למשל מקישור `otzaria://open/gematria?q=...`.
class ToolQuery {
  const ToolQuery(this.text, {this.hebrewToAramaic = false});

  final String text;

  /// כיוון החיפוש במילון הארמי. שאר הכלים מתעלמים ממנו.
  final bool hebrewToAramaic;

  /// הכלים שמסכיהם יודעים לקבל [ToolQuery] — רק להם הראוטר מצרף `q=`.
  static const Set<String> supportedToolIds = {
    'builtin.biographies',
    'builtin.acronyms_dictionary',
    'builtin.aramaic_dictionary',
    'builtin.gematria',
    'builtin.marker',
  };
}

/// תיבת הבקשות של טאב כלי: הקישור מפקיד בקשה, ומסך הכלי לוקח אותה כשהוא
/// מוכן. הבקשה נשמרת עד שנלקחה, כי התוכן נבנה רק כשהטאב מוצג.
class ToolQueryInbox extends ChangeNotifier {
  ToolQuery? _pending;

  void post(ToolQuery query) {
    _pending = query;
    notifyListeners();
  }

  /// מחזיר ומוחק — כל בקשה מוחלת פעם אחת, גם אם המסך נבנה מחדש.
  ToolQuery? take() {
    final query = _pending;
    _pending = null;
    return query;
  }
}

/// מחבר מסך כלי ל-[ToolQueryInbox]. מסך שטוען נתונים מחזיר `false`
/// מ-[canApplyToolQuery] עד סוף הטעינה, ואז קורא ל-[consumeToolQuery].
mixin ToolQueryConsumer<T extends StatefulWidget> on State<T> {
  ToolQueryInbox? get toolQueryInbox;

  bool get canApplyToolQuery => true;

  void applyToolQuery(ToolQuery query);

  @override
  void initState() {
    super.initState();
    toolQueryInbox?.addListener(consumeToolQuery);
    // setState אסור בתוך initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => consumeToolQuery());
  }

  @override
  void dispose() {
    toolQueryInbox?.removeListener(consumeToolQuery);
    super.dispose();
  }

  void consumeToolQuery() {
    if (!mounted || !canApplyToolQuery) return;
    final query = toolQueryInbox?.take();
    if (query != null) applyToolQuery(query);
  }
}

/// ממלא שדה חיפוש בטקסט מבקשה, עם הסמן בסופו.
void fillSearchField(TextEditingController controller, String text) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}
