import 'package:flutter/foundation.dart';

/// יעד הטקסט: גוף הספר או המפרשים (כולל קישורים ותצוגות מקדימות).
enum TextTarget { body, commentary }

/// מצב התצוגה של הכרטיסייה.
enum TextView { regular, pageShape }

/// הערוץ שבו הטקסט מוגש למשתמש.
enum TextChannel { display, copy, export }

/// חריץ הגדרה: שילוב של יעד × תצוגה × ערוץ. 12 חריצים בסך הכול.
///
/// כל חריץ יורש ממה שמעליו לפי [inheritanceChain] — כך שמשתמש שמגדיר רק את
/// השורש (גוף, רגילה, תצוגה) מקבל התנהגות אחידה בכל מקום.
@immutable
class TextDisplaySlot {
  final TextTarget target;
  final TextView view;
  final TextChannel channel;

  const TextDisplaySlot({
    required this.target,
    required this.view,
    required this.channel,
  });

  /// השורש — היחיד שאינו יורש מאף חריץ.
  static const TextDisplaySlot root = TextDisplaySlot(
    target: TextTarget.body,
    view: TextView.regular,
    channel: TextChannel.display,
  );

  static const TextDisplaySlot commentaryDisplay = TextDisplaySlot(
    target: TextTarget.commentary,
    view: TextView.regular,
    channel: TextChannel.display,
  );

  bool get isRoot => this == root;

  /// מפתח יציב לאחסון: `body.regular.display`.
  String get key => '${target.name}.${view.name}.${channel.name}';

  static TextDisplaySlot? fromKey(String key) {
    final parts = key.split('.');
    if (parts.length != 3) return null;
    final target = TextTarget.values.asNameMap()[parts[0]];
    final view = TextView.values.asNameMap()[parts[1]];
    final channel = TextChannel.values.asNameMap()[parts[2]];
    if (target == null || view == null || channel == null) return null;
    return TextDisplaySlot(target: target, view: view, channel: channel);
  }

  /// כל 12 החריצים.
  static List<TextDisplaySlot> get all => [
    for (final channel in TextChannel.values)
      for (final view in TextView.values)
        for (final target in TextTarget.values)
          TextDisplaySlot(target: target, view: view, channel: channel),
  ];

  TextDisplaySlot copyWith({
    TextTarget? target,
    TextView? view,
    TextChannel? channel,
  }) => TextDisplaySlot(
    target: target ?? this.target,
    view: view ?? this.view,
    channel: channel ?? this.channel,
  );

  /// שרשרת הירושה מהחריץ עצמו ועד השורש, מהספציפי לכללי.
  ///
  /// סדר ההכללה: תחילה התצוגה (צורת הדף → רגילה), אחר כך היעד
  /// (מפרשים → גוף), ולבסוף הערוץ (העתקה/ייצוא → תצוגה). כך העתקה משקפת את
  /// התצוגה כברירת מחדל, והגדרה למפרשים גוברת על הגדרה לצורת הדף של הגוף.
  List<TextDisplaySlot> get inheritanceChain {
    final chain = <TextDisplaySlot>[];
    for (final c in _generalizations(channel, TextChannel.display)) {
      for (final t in _generalizations(target, TextTarget.body)) {
        for (final v in _generalizations(view, TextView.regular)) {
          final slot = TextDisplaySlot(target: t, view: v, channel: c);
          if (!chain.contains(slot)) chain.add(slot);
        }
      }
    }
    return chain;
  }

  static List<T> _generalizations<T>(T specific, T general) =>
      specific == general ? [general] : [specific, general];

  @override
  bool operator ==(Object other) =>
      other is TextDisplaySlot &&
      target == other.target &&
      view == other.view &&
      channel == other.channel;

  @override
  int get hashCode => Object.hash(target, view, channel);

  @override
  String toString() => 'TextDisplaySlot($key)';
}
