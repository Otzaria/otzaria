import 'package:flutter/services.dart';

// עוקף לבאג מנוע Flutter (flutter/flutter#178945): סמן בשורת RTL שמסתיימת
// ב-\n מוסט; \r לפני ה-\n מונע זאת. משמש רק לטקסט המוצג ב-RtlTextField.

final RegExp _anyCarriageReturn = RegExp(r'\r\n?');
final RegExp _anyNewline = RegExp(r'\r\n|\n');

/// הופך כל \r\n ו-\r בודד ל-\n. \r בודד נשמר כשבירת שורה ולא נמחק.
String collapseHardBreaks(String text) =>
    text.contains('\r') ? text.replaceAll(_anyCarriageReturn, '\n') : text;

/// offset שנמצא בין \r ל-\n של אותו שבר זז לפני השבר.
int snapOffsetOutOfCrlf(String text, int offset) {
  if (offset > 0 &&
      offset < text.length &&
      text.codeUnitAt(offset - 1) == 13 &&
      text.codeUnitAt(offset) == 10) {
    return offset - 1;
  }
  return offset;
}

/// מיפוי שבירות שורה שנבנה רק כאשר הטקסט משתנה; בחירה ממופה בחיפוש בינארי.
class HardBreakValueMapper {
  HardBreakValueMapper({required this.expand});

  final bool expand;
  String? _source;
  String _target = '';
  final List<int> _breaks = [];

  TextEditingValue map(TextEditingValue value, {String? matchingText}) {
    if (!identical(value.text, _source)) {
      if (value.text != _source) {
        _mapText(value.text);
      } else {
        if (identical(_source, _target)) _target = value.text;
        _source = value.text;
      }
    }
    // שומרים גם זהות מחרוזות בין שני ה-controllers, כדי שהשוואת ערכים
    // בעת שינוי בחירה לא תשווה שוב את כל המסמך.
    if (matchingText != null && _target == matchingText) _target = matchingText;
    if (identical(_source, _target)) return value;
    final selection = value.selection;
    final composing = value.composing;
    return value.copyWith(
      text: _target,
      selection: selection.copyWith(
        baseOffset: _mapOffset(selection.baseOffset),
        extentOffset: _mapOffset(selection.extentOffset),
      ),
      composing: TextRange(
        start: _mapOffset(composing.start),
        end: _mapOffset(composing.end),
      ),
    );
  }

  void _mapText(String text) {
    _source = text;
    _breaks.clear();
    final buffer = StringBuffer();
    var start = 0;
    final matches = expand
        ? _anyNewline.allMatches(text)
        : _anyCarriageReturn.allMatches(text);
    for (final match in matches) {
      if (expand && match.group(0) == '\r\n') continue;
      buffer.write(text.substring(start, match.start));
      buffer.write(expand ? '\r\n' : '\n');
      if (expand || match.end - match.start == 2) _breaks.add(match.start);
      start = match.end;
    }
    if (start == 0) {
      _target = text;
    } else {
      buffer.write(text.substring(start));
      _target = buffer.toString();
    }
  }

  int _mapOffset(int offset) {
    if (offset < 0) return offset;
    if (!expand) offset = snapOffsetOutOfCrlf(_source!, offset);
    var low = 0;
    var high = _breaks.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_breaks[middle] < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return expand ? offset + low : offset - low;
  }
}

/// מרחיב שבירות שורה וממפה יחד בחירה ו-composing.
TextEditingValue expandValue(TextEditingValue value) =>
    HardBreakValueMapper(expand: true).map(value);

/// מנקה שבירות שורה וממפה יחד בחירה ו-composing.
TextEditingValue collapseValue(TextEditingValue value) =>
    HardBreakValueMapper(expand: false).map(value);

/// מרחיב בכל עריכה, כדי ש-\n שהוקלד זה עתה לא יוצג אפילו פריים אחד בלי \r.
/// בזמן composing של IME לא נוגעים (שינוי באמצע מבטל את המילה המוצעת).
class HardBreakInputFormatter extends TextInputFormatter {
  const HardBreakInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.composing.isValid && !newValue.composing.isCollapsed
      ? newValue
      : expandValue(newValue);
}

/// מריץ formatters של הקורא על הטקסט הנקי, כדי שה-\r הפנימי לא ישפיע
/// על מגבלות אורך או תווים.
class CleanSpaceFormatterAdapter extends TextInputFormatter {
  const CleanSpaceFormatterAdapter(this.inner);

  final List<TextInputFormatter> inner;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final cleanOld = collapseValue(oldValue);
    var cleanNew = collapseValue(newValue);
    for (final formatter in inner) {
      cleanNew = formatter.formatEditUpdate(cleanOld, cleanNew);
    }
    return const HardBreakInputFormatter().formatEditUpdate(cleanOld, cleanNew);
  }
}
