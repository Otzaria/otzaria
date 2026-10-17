import 'package:flutter/foundation.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

/// הצגה/הסתרה של קבוצת סימנים (ניקוד, פיסוק, ציוני מפרשים).
enum MarkVisibility {
  show,
  hide;

  static MarkVisibility? fromJson(Object? value) => switch (value) {
    'show' => MarkVisibility.show,
    'hide' => MarkVisibility.hide,
    _ => null,
  };
}

/// הצגת הטעמים. [followNikud] — הטעמים מוסתרים יחד עם הניקוד ומוצגים איתו.
enum TeamimVisibility {
  show,
  hide,
  followNikud;

  static TeamimVisibility? fromJson(Object? value) => switch (value) {
    'show' => TeamimVisibility.show,
    'hide' => TeamimVisibility.hide,
    'followNikud' => TeamimVisibility.followNikud,
    _ => null,
  };
}

/// הצגת שם הוי"ה: ככתבו, או מוחלף באחד הסגנונות של [HolyNameStyle].
enum HolyNameDisplay {
  asIs,
  kufKuf,
  hehApostrophe,
  doubleYod;

  /// null = הצגה ככתבו (אין החלפה).
  HolyNameStyle? get style => switch (this) {
    HolyNameDisplay.asIs => null,
    HolyNameDisplay.kufKuf => HolyNameStyle.kufKuf,
    HolyNameDisplay.hehApostrophe => HolyNameStyle.hehApostrophe,
    HolyNameDisplay.doubleYod => HolyNameStyle.doubleYod,
  };

  static HolyNameDisplay fromLegacy({
    required bool replaceHolyNames,
    required HolyNameStyle style,
  }) {
    if (!replaceHolyNames) return HolyNameDisplay.asIs;
    return switch (style) {
      HolyNameStyle.kufKuf => HolyNameDisplay.kufKuf,
      HolyNameStyle.hehApostrophe => HolyNameDisplay.hehApostrophe,
      HolyNameStyle.doubleYod => HolyNameDisplay.doubleYod,
    };
  }

  static HolyNameDisplay? fromJson(Object? value) => switch (value) {
    'asIs' => HolyNameDisplay.asIs,
    'kufKuf' => HolyNameDisplay.kufKuf,
    'hehApostrophe' => HolyNameDisplay.hehApostrophe,
    'doubleYod' => HolyNameDisplay.doubleYod,
    _ => null,
  };
}

/// הצגת שמות הקודש שאינם שם הוי"ה (אלהים, שדי וכד'): ככתבם, או בצורת
/// התצוגה שלהם. חל רק על מופעים שסומנו במסד (`line_divine_name`).
enum DivineNamesDisplay {
  asIs,
  substitute;

  static DivineNamesDisplay? fromJson(Object? value) => switch (value) {
    'asIs' => DivineNamesDisplay.asIs,
    'substitute' => DivineNamesDisplay.substitute,
    _ => null,
  };
}

/// פרופיל תצוגת טקסט מלא — מה מוצג ומה מוסתר בטקסט עברי.
///
/// זהו הערך שכל צרכן (רינדור, העתקה, ייצוא) מקבל פתור, בלי שדות חסרים.
/// הרכבתו מטלאים חלקיים נעשית ב-`TextDisplayResolver`.
@immutable
class TextDisplayProfile {
  final MarkVisibility nikud;
  final TeamimVisibility teamim;
  final MarkVisibility punctuation;
  final HolyNameDisplay holyName;

  /// ציוני המפרשים בגוף הטקסט — אותיות העוגן, למשל (א).
  final MarkVisibility anchorMarkers;

  /// שאר שמות הקודש — כבוי כברירת מחדל עד לאישור הצורות.
  final DivineNamesDisplay divineNames;

  const TextDisplayProfile({
    this.nikud = MarkVisibility.show,
    this.teamim = TeamimVisibility.followNikud,
    this.punctuation = MarkVisibility.show,
    this.holyName = HolyNameDisplay.kufKuf,
    this.anchorMarkers = MarkVisibility.show,
    this.divineNames = DivineNamesDisplay.asIs,
  });

  /// ברירת המחדל של התוכנה: הכול מוצג, שם הוי"ה מוחלף ביקוק.
  static const TextDisplayProfile defaults = TextDisplayProfile();

  bool get removeNikud => nikud == MarkVisibility.hide;

  bool get removeTeamim => switch (teamim) {
    TeamimVisibility.show => false,
    TeamimVisibility.hide => true,
    TeamimVisibility.followNikud => removeNikud,
  };

  bool get removePunctuation => punctuation == MarkVisibility.hide;
  bool get replaceHolyNames => holyName != HolyNameDisplay.asIs;
  HolyNameStyle get holyNameStyle => holyName.style ?? HolyNameStyle.kufKuf;
  bool get showAnchorMarkers => anchorMarkers == MarkVisibility.show;
  bool get substituteDivineNames =>
      divineNames == DivineNamesDisplay.substitute;

  TextDisplayProfile copyWith({
    MarkVisibility? nikud,
    TeamimVisibility? teamim,
    MarkVisibility? punctuation,
    HolyNameDisplay? holyName,
    MarkVisibility? anchorMarkers,
    DivineNamesDisplay? divineNames,
  }) {
    return TextDisplayProfile(
      nikud: nikud ?? this.nikud,
      teamim: teamim ?? this.teamim,
      punctuation: punctuation ?? this.punctuation,
      holyName: holyName ?? this.holyName,
      anchorMarkers: anchorMarkers ?? this.anchorMarkers,
      divineNames: divineNames ?? this.divineNames,
    );
  }

  /// הטלאי שמייצג את הפרופיל במלואו (כל השדות מלאים).
  TextDisplayPatch toPatch() => TextDisplayPatch(
    nikud: nikud,
    teamim: teamim,
    punctuation: punctuation,
    holyName: holyName,
    anchorMarkers: anchorMarkers,
    divineNames: divineNames,
  );

  @override
  bool operator ==(Object other) =>
      other is TextDisplayProfile &&
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

  @override
  String toString() =>
      'TextDisplayProfile(nikud: ${nikud.name}, teamim: ${teamim.name}, '
      'punctuation: ${punctuation.name}, holyName: ${holyName.name}, '
      'anchorMarkers: ${anchorMarkers.name}, divineNames: ${divineNames.name})';
}

/// טלאי חלקי על פרופיל: שדה null = "ירש מלמעלה".
@immutable
class TextDisplayPatch {
  final MarkVisibility? nikud;
  final TeamimVisibility? teamim;
  final MarkVisibility? punctuation;
  final HolyNameDisplay? holyName;
  final MarkVisibility? anchorMarkers;
  final DivineNamesDisplay? divineNames;

  const TextDisplayPatch({
    this.nikud,
    this.teamim,
    this.punctuation,
    this.holyName,
    this.anchorMarkers,
    this.divineNames,
  });

  static const TextDisplayPatch empty = TextDisplayPatch();

  bool get isEmpty =>
      nikud == null &&
      teamim == null &&
      punctuation == null &&
      holyName == null &&
      anchorMarkers == null &&
      divineNames == null;

  bool get isNotEmpty => !isEmpty;

  /// מיזוג: השדות של [other] גוברים על השדות של הטלאי הנוכחי.
  TextDisplayPatch merge(TextDisplayPatch other) => TextDisplayPatch(
    nikud: other.nikud ?? nikud,
    teamim: other.teamim ?? teamim,
    punctuation: other.punctuation ?? punctuation,
    holyName: other.holyName ?? holyName,
    anchorMarkers: other.anchorMarkers ?? anchorMarkers,
    divineNames: other.divineNames ?? divineNames,
  );

  /// הפרופיל שמתקבל מהחלת הטלאי על [base].
  TextDisplayProfile applyTo(TextDisplayProfile base) => base.copyWith(
    nikud: nikud,
    teamim: teamim,
    punctuation: punctuation,
    holyName: holyName,
    anchorMarkers: anchorMarkers,
    divineNames: divineNames,
  );

  /// עותק שבו השדות ששווים ל-[base] נמחקים — כך שהטלאי מכיל רק סטיות
  /// אמיתיות והספר יירש שינויים עתידיים בברירת המחדל.
  TextDisplayPatch pruneAgainst(TextDisplayProfile base) => TextDisplayPatch(
    nikud: nikud == base.nikud ? null : nikud,
    teamim: teamim == base.teamim ? null : teamim,
    punctuation: punctuation == base.punctuation ? null : punctuation,
    holyName: holyName == base.holyName ? null : holyName,
    anchorMarkers: anchorMarkers == base.anchorMarkers ? null : anchorMarkers,
    divineNames: divineNames == base.divineNames ? null : divineNames,
  );

  TextDisplayPatch copyWith({
    MarkVisibility? nikud,
    TeamimVisibility? teamim,
    MarkVisibility? punctuation,
    HolyNameDisplay? holyName,
    MarkVisibility? anchorMarkers,
    DivineNamesDisplay? divineNames,
    bool clearNikud = false,
    bool clearTeamim = false,
    bool clearPunctuation = false,
    bool clearHolyName = false,
    bool clearAnchorMarkers = false,
    bool clearDivineNames = false,
  }) {
    return TextDisplayPatch(
      nikud: clearNikud ? null : (nikud ?? this.nikud),
      teamim: clearTeamim ? null : (teamim ?? this.teamim),
      punctuation: clearPunctuation ? null : (punctuation ?? this.punctuation),
      holyName: clearHolyName ? null : (holyName ?? this.holyName),
      anchorMarkers: clearAnchorMarkers
          ? null
          : (anchorMarkers ?? this.anchorMarkers),
      divineNames: clearDivineNames ? null : (divineNames ?? this.divineNames),
    );
  }

  Map<String, dynamic> toJson() => {
    if (nikud != null) 'nikud': nikud!.name,
    if (teamim != null) 'teamim': teamim!.name,
    if (punctuation != null) 'punctuation': punctuation!.name,
    if (holyName != null) 'holyName': holyName!.name,
    if (anchorMarkers != null) 'anchorMarkers': anchorMarkers!.name,
    if (divineNames != null) 'divineNames': divineNames!.name,
  };

  /// ערך לא מוכר בשדה נחשב null (ירושה) — קובץ פגום לא מפיל את הטעינה.
  factory TextDisplayPatch.fromJson(Map<String, dynamic> json) =>
      TextDisplayPatch(
        nikud: MarkVisibility.fromJson(json['nikud']),
        teamim: TeamimVisibility.fromJson(json['teamim']),
        punctuation: MarkVisibility.fromJson(json['punctuation']),
        holyName: HolyNameDisplay.fromJson(json['holyName']),
        anchorMarkers: MarkVisibility.fromJson(json['anchorMarkers']),
        divineNames: DivineNamesDisplay.fromJson(json['divineNames']),
      );

  @override
  bool operator ==(Object other) =>
      other is TextDisplayPatch &&
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

  @override
  String toString() => 'TextDisplayPatch(${toJson()})';
}
