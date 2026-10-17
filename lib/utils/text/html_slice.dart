import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

/// חותך מתוך [html] את החלק שמכוסה ע"י [selectedText], עם התגיות שעוטפות
/// אותו, ומחזיר null כשאין התאמה חד-משמעית.
///
/// הטקסט נלקח מ-[selectedText] והמבנה מ-[html], ולכן התוצאה תואמת תמיד
/// למה שנבחר על המסך — גם כשהתצוגה מסתירה ניקוד, טעמים או פיסוק.
/// כשאותו טקסט חוזר בשורה ביותר ממקום אחד ועיצובו שונה, מוחזר null:
/// אי אפשר לדעת איזה מופע נבחר, ועדיף טקסט פשוט על עיצוב שגוי.
String? sliceHtmlBySelection({
  required String html,
  required String selectedText,
}) {
  if (html.isEmpty || selectedText.trim().isEmpty) {
    return null;
  }

  final fragment = html_parser.parseFragment(html);
  final slots = <_Slot>[];
  final rawText = StringBuffer();
  _collectSlots(fragment.nodes, slots, rawText);
  if (slots.isEmpty) {
    return null;
  }

  final source = _MatchKey.from(rawText.toString());
  final selection = _MatchKey.from(selectedText);
  if (selection.key.isEmpty) {
    return null;
  }

  // המופעים נאספים לפני החיתוך, כדי לא לשלם על חיתוכים שיושלכו ממילא.
  final matches = <int>[];
  var matchStart = source.key.indexOf(selection.key);
  while (matchStart >= 0) {
    matches.add(matchStart);
    if (matches.length > _maxOccurrences) {
      return null;
    }
    matchStart = source.key.indexOf(selection.key, matchStart + 1);
  }
  if (matches.isEmpty) {
    return null;
  }

  String? sliced;
  for (final start in matches) {
    final candidate = _buildSlice(
      fragment: fragment,
      slots: slots,
      source: source,
      selection: selection,
      matchStart: start,
      selectedText: selectedText,
    );
    if (candidate == null || (sliced != null && sliced != candidate)) {
      return null;
    }
    sliced = candidate;
  }

  return sliced;
}

/// כל מופע נחתך מחדש כדי להשוות בין התוצאות, ולכן שורה ארוכה שבה הבחירה
/// חוזרת עשרות פעמים הופכת יקרה. מעבר לתקרה ההתאמה ממילא אינה חד-משמעית.
const _maxOccurrences = 12;

String? _buildSlice({
  required dom.DocumentFragment fragment,
  required List<_Slot> slots,
  required _MatchKey source,
  required _MatchKey selection,
  required int matchStart,
  required String selectedText,
}) {
  final ranges = _mapSelectionToSlots(
    slots: slots,
    source: source,
    selection: selection,
    matchStart: matchStart,
    selectionLength: selectedText.length,
  );
  if (ranges.isEmpty) {
    return null;
  }

  final container = dom.Element.tag('div');
  for (final node in fragment.nodes) {
    final pruned = _prune(node, ranges, selectedText);
    if (pruned != null) {
      container.nodes.add(pruned);
    }
  }

  final sliced = container.innerHtml;
  return sliced.isEmpty ? null : sliced;
}

/// קטע טקסט רציף במסמך, עם מיקומו במחרוזת הטקסט המצטברת.
class _Slot {
  const _Slot(this.node, this.start, this.end);

  final dom.Node node;
  final int start;
  final int end;
}

/// אוסף את קטעי הטקסט לפי סדר המסמך. `<br>` נספר כמעבר שורה, וגוף הערת
/// שוליים מדולג — הקורא מסיר אותו מהתצוגה, ולכן אסור להתאים אליו.
void _collectSlots(
  List<dom.Node> nodes,
  List<_Slot> slots,
  StringBuffer rawText,
) {
  for (final node in nodes) {
    if (node is dom.Text) {
      final data = node.data;
      if (data.isEmpty) continue;
      slots.add(_Slot(node, rawText.length, rawText.length + data.length));
      rawText.write(data);
      continue;
    }

    if (node is! dom.Element) continue;

    if (node.localName == 'br') {
      slots.add(_Slot(node, rawText.length, rawText.length + 1));
      rawText.write('\n');
      continue;
    }

    if (_isFootnoteBody(node)) continue;

    _collectSlots(node.nodes, slots, rawText);
  }
}

bool _isFootnoteBody(dom.Element element) =>
    element.localName == 'i' &&
    (element.attributes['class'] ?? '').contains('footnote');

/// מפתח השוואה שמדמה את מה שהקורא מציג — בלי ניקוד, טעמים ופיסוק, עם
/// רווחים מכווצים ועם שם הוי"ה מוחלף — לצד המיקום המקורי של כל תו.
class _MatchKey {
  const _MatchKey(this.key, this.offsets);

  final String key;
  final List<int> offsets;

  factory _MatchKey.from(String text) {
    // ההחלפה מוחלת על שני צדי ההשוואה, כדי שההתאמה תעבוד בלי תלות בהגדרת
    // "החלפת שמות קדושים". היא שומרת על האורך, ולכן המיקומים נשארים תקפים.
    final replaced = text_utils.replaceHolyNames(text);
    final normalized = replaced.length == text.length ? replaced : text;

    final key = StringBuffer();
    final offsets = <int>[];
    int? pendingSpaceAt;

    for (var i = 0; i < normalized.length; i++) {
      final codeUnit = normalized.codeUnitAt(i);
      if (_isIgnored(codeUnit)) continue;

      if (_isSpacing(codeUnit)) {
        pendingSpaceAt ??= i;
        continue;
      }

      if (pendingSpaceAt != null) {
        if (key.isNotEmpty) {
          key.write(' ');
          offsets.add(pendingSpaceAt);
        }
        pendingSpaceAt = null;
      }

      key.write(normalized[i]);
      offsets.add(i);
    }

    return _MatchKey(key.toString(), offsets);
  }
}

/// תווים שהקורא עשוי להציג כרווח: רווחים ממש, ומפרידי הטקסט המקראי
/// שגם [text_utils.removeVolwels] הופך לרווח.
bool _isSpacing(int codeUnit) =>
    codeUnit == 0x20 || // רווח
    codeUnit == 0x09 || // טאב
    codeUnit == 0x0A || // מעבר שורה
    codeUnit == 0x0D || // גרירת שורה
    codeUnit == 0xA0 || // רווח קשיח
    codeUnit == 0x05BE || // מקף
    codeUnit == 0x05C0 || // פסק
    codeUnit == 0x7C; // קו אנכי

/// תווים שהקורא עשוי להשמיט לגמרי: ניקוד וטעמים, וסימני הפיסוק
/// ש-[text_utils.removePunctuation] מסיר.
bool _isIgnored(int codeUnit) {
  if (codeUnit >= 0x0591 && codeUnit <= 0x05C7) {
    return !_isSpacing(codeUnit);
  }

  return codeUnit == 0x21 || // !
      codeUnit == 0x22 || // "
      codeUnit == 0x27 || // '
      codeUnit == 0x2C || // ,
      codeUnit == 0x2D || // -
      codeUnit == 0x2E || // .
      codeUnit == 0x3A || // :
      codeUnit == 0x3B || // ;
      codeUnit == 0x3F || // ?
      codeUnit == 0x05F3 || // ׳
      codeUnit == 0x05F4 || // ״
      codeUnit == 0x2013 || // –
      codeUnit == 0x2014 || // —
      codeUnit == 0x2060; // מחבר מילים (אחרי המקף בצורות שמות הקודש)
}

/// משייך לכל קטע טקסט את הטווח שלו בתוך הבחירה. הטווח נמתח מקצה לקצה
/// הבחירה, כך שפיסוק, ניקוד ורווחים שנשמטו מהמפתח בקצוות אינם נבלעים.
Map<dom.Node, ({int start, int end})> _mapSelectionToSlots({
  required List<_Slot> slots,
  required _MatchKey source,
  required _MatchKey selection,
  required int matchStart,
  required int selectionLength,
}) {
  final ranges = <dom.Node, ({int start, int end})>{};
  final length = selection.key.length;
  var slotIndex = 0;

  for (var i = 0; i < length; i++) {
    final sourceOffset = source.offsets[matchStart + i];
    while (slotIndex < slots.length && sourceOffset >= slots[slotIndex].end) {
      slotIndex++;
    }
    if (slotIndex >= slots.length) break;

    final slot = slots[slotIndex];
    final start = i == 0 ? 0 : selection.offsets[i];
    final end = i + 1 < length ? selection.offsets[i + 1] : selectionLength;
    final existing = ranges[slot.node];
    ranges[slot.node] = (start: existing?.start ?? start, end: end);
  }

  return ranges;
}

dom.Node? _prune(
  dom.Node node,
  Map<dom.Node, ({int start, int end})> ranges,
  String selectedText,
) {
  if (node is dom.Text) {
    final range = ranges[node];
    if (range == null) return null;
    final text = selectedText.substring(range.start, range.end);
    return text.isEmpty ? null : dom.Text(text);
  }

  if (node is! dom.Element) return null;

  if (node.localName == 'br') {
    return ranges.containsKey(node) ? node.clone(false) : null;
  }

  if (_isFootnoteBody(node)) return null;

  final children = <dom.Node>[];
  for (final child in node.nodes) {
    final pruned = _prune(child, ranges, selectedText);
    if (pruned != null) children.add(pruned);
  }
  if (children.isEmpty) return null;

  final clone = node.clone(false);
  clone.nodes.addAll(children);
  return clone;
}
