import 'package:flutter/foundation.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

/// מה לעשות לשדה הצג/הסתר כשהקיצור מופעל. null = לא לגעת.
enum DynamicMarkChange {
  show,
  hide,
  toggle;

  static DynamicMarkChange? fromJson(Object? v) =>
      values.asNameMap()[v is String ? v : ''];

  MarkVisibility apply(MarkVisibility current) => switch (this) {
    show => MarkVisibility.show,
    hide => MarkVisibility.hide,
    toggle =>
      current == MarkVisibility.show
          ? MarkVisibility.hide
          : MarkVisibility.show,
  };
}

/// מה לעשות לטעמים כשהקיצור מופעל. null = לא לגעת.
enum DynamicTeamimChange {
  show,
  hide,
  followNikud,
  toggle;

  static DynamicTeamimChange? fromJson(Object? v) =>
      values.asNameMap()[v is String ? v : ''];

  TeamimVisibility apply(TextDisplayProfile current) => switch (this) {
    show => TeamimVisibility.show,
    hide => TeamimVisibility.hide,
    followNikud => TeamimVisibility.followNikud,
    toggle =>
      current.removeTeamim ? TeamimVisibility.show : TeamimVisibility.hide,
  };
}

/// סוג הפעולה הדינמית.
enum DynamicShortcutKind {
  /// שינוי תצוגת הטקסט בכרטיסייה הפעילה (ואופציונלית שמירה לספר).
  setTextDisplay,

  /// העתקת הטקסט המסומן עם פרופיל שונה מערוץ ההעתקה.
  copySelectionWith,

  /// העתקת הפסקה הנבחרת עם פרופיל שונה מערוץ ההעתקה.
  copyParagraphWith;

  static DynamicShortcutKind? fromJson(Object? v) =>
      values.asNameMap()[v is String ? v : ''];
}

/// השינוי שהמשתמש הגדיר לקיצור: שדה null אינו משתנה.
@immutable
class DynamicDisplayChange {
  final DynamicMarkChange? nikud;
  final DynamicTeamimChange? teamim;
  final DynamicMarkChange? punctuation;
  final HolyNameDisplay? holyName;
  final DynamicMarkChange? anchorMarkers;
  final DivineNamesDisplay? divineNames;

  const DynamicDisplayChange({
    this.nikud,
    this.teamim,
    this.punctuation,
    this.holyName,
    this.anchorMarkers,
    this.divineNames,
  });

  bool get isEmpty =>
      nikud == null &&
      teamim == null &&
      punctuation == null &&
      holyName == null &&
      anchorMarkers == null &&
      divineNames == null;

  /// הטלאי שנוצר מהחלת השינוי על הפרופיל הפתור כעת.
  TextDisplayPatch patchFor(TextDisplayProfile current) => TextDisplayPatch(
    nikud: nikud?.apply(current.nikud),
    teamim: teamim?.apply(current),
    punctuation: punctuation?.apply(current.punctuation),
    holyName: holyName,
    anchorMarkers: anchorMarkers?.apply(current.anchorMarkers),
    divineNames: divineNames,
  );

  DynamicDisplayChange copyWith({
    Object? nikud = _keep,
    Object? teamim = _keep,
    Object? punctuation = _keep,
    Object? holyName = _keep,
    Object? anchorMarkers = _keep,
    Object? divineNames = _keep,
  }) => DynamicDisplayChange(
    nikud: nikud == _keep ? this.nikud : nikud as DynamicMarkChange?,
    teamim: teamim == _keep ? this.teamim : teamim as DynamicTeamimChange?,
    punctuation: punctuation == _keep
        ? this.punctuation
        : punctuation as DynamicMarkChange?,
    holyName: holyName == _keep ? this.holyName : holyName as HolyNameDisplay?,
    anchorMarkers: anchorMarkers == _keep
        ? this.anchorMarkers
        : anchorMarkers as DynamicMarkChange?,
    divineNames: divineNames == _keep
        ? this.divineNames
        : divineNames as DivineNamesDisplay?,
  );

  static const Object _keep = Object();

  Map<String, dynamic> toJson() => {
    if (nikud != null) 'nikud': nikud!.name,
    if (teamim != null) 'teamim': teamim!.name,
    if (punctuation != null) 'punctuation': punctuation!.name,
    if (holyName != null) 'holyName': holyName!.name,
    if (anchorMarkers != null) 'anchorMarkers': anchorMarkers!.name,
    if (divineNames != null) 'divineNames': divineNames!.name,
  };

  factory DynamicDisplayChange.fromJson(Map<String, dynamic> json) =>
      DynamicDisplayChange(
        nikud: DynamicMarkChange.fromJson(json['nikud']),
        teamim: DynamicTeamimChange.fromJson(json['teamim']),
        punctuation: DynamicMarkChange.fromJson(json['punctuation']),
        holyName: HolyNameDisplay.fromJson(json['holyName']),
        anchorMarkers: DynamicMarkChange.fromJson(json['anchorMarkers']),
        divineNames: DivineNamesDisplay.fromJson(json['divineNames']),
      );

  @override
  bool operator ==(Object other) =>
      other is DynamicDisplayChange &&
      nikud == other.nikud &&
      teamim == other.teamim &&
      punctuation == other.punctuation &&
      holyName == other.holyName &&
      anchorMarkers == other.anchorMarkers &&
      divineNames == other.divineNames;

  @override
  int get hashCode => Object.hash(
    nikud,
    teamim,
    punctuation,
    holyName,
    anchorMarkers,
    divineNames,
  );
}

/// קיצור מקלדת לפעולה דינמית: המשתמש בוחר את הפעולה ואת הפרמטרים שלה
/// בעת הגדרת הקיצור, ולא מתוך רשימה סגורה של פעולות.
@immutable
class DynamicShortcut {
  final String id;

  /// הקיצור בפורמט קנוני (`ctrl+shift+n`); ריק = לא הוגדר מקש.
  final String key;
  final DynamicShortcutKind kind;
  final TextTarget target;
  final DynamicDisplayChange change;

  /// ב-[DynamicShortcutKind.setTextDisplay]: לשמור גם לקובץ הספר.
  final bool persistToBook;

  /// בפעולות ההעתקה: טקסט פשוט בלבד, בלי HTML מעוצב (issue #1299).
  final bool plainTextOnly;

  const DynamicShortcut({
    required this.id,
    required this.key,
    required this.kind,
    this.target = TextTarget.body,
    required this.change,
    this.persistToBook = false,
    this.plainTextOnly = false,
  });

  bool get isCopy => kind != DynamicShortcutKind.setTextDisplay;

  /// האם לקיצור יש השפעה כלשהי — שינוי תצוגה, או העתקה ללא עיצוב.
  bool get hasEffect => !change.isEmpty || (isCopy && plainTextOnly);

  /// מפתח ההגדרה הסינתטי שבו הקיצור נרשם ב-`ShortcutValidator`.
  String get settingKey => '$settingKeyPrefix$id';
  static const String settingKeyPrefix = 'key-shortcut-dynamic-';

  DynamicShortcut copyWith({
    String? key,
    DynamicShortcutKind? kind,
    TextTarget? target,
    DynamicDisplayChange? change,
    bool? persistToBook,
    bool? plainTextOnly,
  }) => DynamicShortcut(
    id: id,
    key: key ?? this.key,
    kind: kind ?? this.kind,
    target: target ?? this.target,
    change: change ?? this.change,
    persistToBook: persistToBook ?? this.persistToBook,
    plainTextOnly: plainTextOnly ?? this.plainTextOnly,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'kind': kind.name,
    'target': target.name,
    'change': change.toJson(),
    'persistToBook': persistToBook,
    'plainTextOnly': plainTextOnly,
  };

  /// null כשהרשומה פגומה (אין מזהה או סוג) — נדלגת בטעינה.
  static DynamicShortcut? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = DynamicShortcutKind.fromJson(json['kind']);
    if (id is! String || id.isEmpty || kind == null) return null;
    final change = json['change'];
    return DynamicShortcut(
      id: id,
      key: json['key'] is String ? json['key'] as String : '',
      kind: kind,
      target: TextTarget.values.asNameMap()[json['target']] ?? TextTarget.body,
      change: change is Map
          ? DynamicDisplayChange.fromJson(Map<String, dynamic>.from(change))
          : const DynamicDisplayChange(),
      persistToBook: json['persistToBook'] == true,
      plainTextOnly: json['plainTextOnly'] == true,
    );
  }

  /// תווית תצוגה בעברית שנגזרת מהפרמטרים, למשל
  /// "הסתר ניקוד, טעמים כמו הניקוד — גוף הספר".
  String describe() {
    final parts = <String>[
      if (change.nikud != null) '${_mark(change.nikud!)} ניקוד',
      if (change.teamim != null)
        switch (change.teamim!) {
          DynamicTeamimChange.show => 'הצג טעמים',
          DynamicTeamimChange.hide => 'הסתר טעמים',
          DynamicTeamimChange.followNikud => 'טעמים כמו הניקוד',
          DynamicTeamimChange.toggle => 'הצג/הסתר טעמים',
        },
      if (change.punctuation != null) '${_mark(change.punctuation!)} פיסוק',
      if (change.holyName != null)
        switch (change.holyName!) {
          HolyNameDisplay.asIs => 'שם הוי"ה ככתבו',
          HolyNameDisplay.kufKuf => 'שם הוי"ה כיקוק',
          HolyNameDisplay.hehApostrophe => "שם הוי\"ה כה'",
        },
      if (change.anchorMarkers != null)
        '${_mark(change.anchorMarkers!)} ציוני מפרשים',
      if (change.divineNames != null)
        switch (change.divineNames!) {
          DivineNamesDisplay.asIs => 'שאר שמות הקודש ככתבם',
          DivineNamesDisplay.substitute => 'שאר שמות הקודש בכינוי',
        },
    ];
    if (isCopy && plainTextOnly) parts.add('ללא עיצוב');
    final what = parts.isEmpty ? 'ללא שינוי' : parts.join(', ');
    final where = target == TextTarget.body ? 'גוף הספר' : 'מפרשים';
    return switch (kind) {
      DynamicShortcutKind.setTextDisplay =>
        '$what — $where${persistToBook ? ' (נשמר לספר)' : ''}',
      DynamicShortcutKind.copySelectionWith => 'העתק בחירה: $what',
      DynamicShortcutKind.copyParagraphWith => 'העתק פסקה: $what',
    };
  }

  static String _mark(DynamicMarkChange c) => switch (c) {
    DynamicMarkChange.show => 'הצג',
    DynamicMarkChange.hide => 'הסתר',
    DynamicMarkChange.toggle => 'הצג/הסתר',
  };

  @override
  bool operator ==(Object other) =>
      other is DynamicShortcut &&
      id == other.id &&
      key == other.key &&
      kind == other.kind &&
      target == other.target &&
      change == other.change &&
      persistToBook == other.persistToBook &&
      plainTextOnly == other.plainTextOnly;

  @override
  int get hashCode => Object.hash(
    id,
    key,
    kind,
    target,
    change,
    persistToBook,
    plainTextOnly,
  );
}
