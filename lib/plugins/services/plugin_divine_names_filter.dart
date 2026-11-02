import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show HolyNameStyle, findReplaceableHolyNames, replaceHolyNames;
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// הצגת שמות הקודש בטקסט שנמסר לתוסף — החלק של השמות מפרופיל התצוגה.
@immutable
class PluginDivineNamesDisplay {
  const PluginDivineNamesDisplay({
    required this.holyName,
    required this.otherNames,
  });

  /// הטקסט כפי שנשמר — לתוסף שביקש `rawDivineNames: true`.
  static const PluginDivineNamesDisplay raw = PluginDivineNamesDisplay(
    holyName: HolyNameDisplay.asIs,
    otherNames: DivineNamesDisplay.asIs,
  );

  factory PluginDivineNamesDisplay.of(TextDisplayProfile profile) =>
      PluginDivineNamesDisplay(
        holyName: profile.holyName,
        otherNames: profile.divineNames,
      );

  factory PluginDivineNamesDisplay.ofSettings(RenderSettings settings) =>
      PluginDivineNamesDisplay(
        holyName: HolyNameDisplay.fromLegacy(
          replaceHolyNames: settings.replaceHolyNames,
          style: settings.holyNameStyle,
        ),
        otherNames: settings.substituteDivineNames
            ? DivineNamesDisplay.substitute
            : DivineNamesDisplay.asIs,
      );

  final HolyNameDisplay holyName;
  final DivineNamesDisplay otherNames;

  HolyNameStyle? get holyNameStyle => holyName.style;
  bool get substituteOtherNames => otherNames == DivineNamesDisplay.substitute;
  bool get filters => holyNameStyle != null || substituteOtherNames;

  /// [profile] עם הצגת השמות הזו במקום שלו.
  TextDisplayProfile applyTo(TextDisplayProfile profile) =>
      profile.copyWith(holyName: holyName, divineNames: otherNames);

  RenderSettings applyToSettings(RenderSettings settings) => settings.copyWith(
    replaceHolyNames: holyNameStyle != null,
    holyNameStyle: holyNameStyle,
    substituteDivineNames: substituteOtherNames,
  );

  Map<String, dynamic> toJson() => {
    'holyName': holyName.name,
    'otherNames': otherNames.name,
    'filtered': filters,
    'holyNameSample': switch (holyNameStyle) {
      null => 'יהוה',
      final style => replaceHolyNames('יהוה', style: style),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is PluginDivineNamesDisplay &&
      other.holyName == holyName &&
      other.otherNames == otherNames;

  @override
  int get hashCode => Object.hash(holyName, otherNames);
}

/// מה תוסף מקבל במקום שמות הקודש: כפי שהקורא היה מציג אותם, לפי ההגדרה
/// ברגע הקריאה — לא לפי צילום המדיניות בכרטיסייה, שמתעדכן רק בטעינה מחדש.
abstract final class PluginDivineNamesFilter {
  @visibleForTesting
  static Future<bool> Function(Book book)? debugIsTanach;

  static TextDisplaySlot _slot(TextTarget target) => TextDisplaySlot(
    target: target,
    view: TextView.regular,
    channel: TextChannel.display,
  );

  /// הפרופיל שהכרטיסייה [state] מציגה עכשיו: שכבותיה מעל המדיניות העדכנית.
  static TextDisplayProfile readerProfile(
    TextBookLoaded state, {
    TextTarget target = TextTarget.body,
  }) => state.displayProfile(
    target: target,
    policy: SettingsRepository().loadTextDisplayPolicy(),
  );

  /// הפרופיל של ספר שאינו פתוח: הגדרות הספר, שכבת התנ"ך והשכבה הכללית.
  /// [namesOnly] — מדלג על טעינת הספר כשהיא לא תשנה את הצגת השמות.
  static Future<TextDisplayProfile> bookProfile(
    Book book, {
    TextTarget target = TextTarget.body,
    bool namesOnly = false,
  }) async {
    final policy = SettingsRepository().loadTextDisplayPolicy();
    final slot = _slot(target);
    final general = policy.resolve(slot);
    final perBookEnabled =
        Settings.getValue<bool>(SettingsRepository.keyEnablePerBookSettings) ??
        false;
    if (namesOnly &&
        !perBookEnabled &&
        PluginDivineNamesDisplay.of(general) ==
            PluginDivineNamesDisplay.of(policy.resolve(slot, isTanach: true))) {
      return general;
    }
    try {
      final isTanach =
          await (debugIsTanach?.call(book) ??
              FileSystemData.instance.isTanachBook(
                book.title,
                categoryId: book.categoryId,
                fileType: book.fileType,
              ));
      final bookLayer = perBookEnabled && book is TextBook
          ? (await TextBookPerBookSettings.load(book))?.effectiveDisplayLayer
          : null;
      return TextDisplayResolver.resolve(
        slot: slot,
        layers: [
          ?bookLayer,
          ...policy.layersFor(isTanach: isTanach),
        ],
      );
    } catch (e) {
      debugPrint('PluginDivineNamesFilter: book display "${book.title}": $e');
      return general;
    }
  }

  /// הצגת השמות ל-[book] (או השכבה הכללית בלעדיו), מ-[readerState] כשהספר
  /// פתוח בו. [raw] — התוסף ביקש את הטקסט כפי שנשמר.
  static Future<PluginDivineNamesDisplay> resolve({
    Book? book,
    TextBookLoaded? readerState,
    TextTarget target = TextTarget.body,
    bool raw = false,
  }) async {
    if (raw) return PluginDivineNamesDisplay.raw;
    if (readerState != null) {
      return PluginDivineNamesDisplay.of(
        readerProfile(readerState, target: target),
      );
    }
    if (book != null) {
      return PluginDivineNamesDisplay.of(
        await bookProfile(book, target: target, namesOnly: true),
      );
    }
    return generalNames(target: target);
  }

  /// הצגת השמות לפי ההגדרה הכללית בלבד, בלי שכבות של ספר.
  static PluginDivineNamesDisplay generalNames({
    TextTarget target = TextTarget.body,
  }) => PluginDivineNamesDisplay.of(
    SettingsRepository().loadTextDisplayPolicy().resolve(_slot(target)),
  );

  /// מופעי השמות במסד של [book]; של הכרטיסייה כשכבר נטענו בה.
  static Future<DivineNameSpans> spansFor(
    Book book, {
    TextBookLoaded? readerState,
  }) {
    final loaded = readerState?.divineNames;
    if (loaded != null && !loaded.isEmpty) return Future.value(loaded);
    return DivineNamesRepository.instance.spansFor(
      book.title,
      categoryId: book.categoryId,
      source: book.source,
      fileType: book.fileType,
      versionTitle: book is TextBook ? book.versionTitle : null,
    );
  }
}

/// שורה [lineIndex] השמורה של ספר שמופעיו [spans], עם השמות לפי [names]. הסמנים
/// מוזרקים על השורה הגולמית, וה-regex תופס את שם הוי"ה שאין לו מופע במסד.
String filterPluginDivineNamesLine(
  String line,
  int lineIndex,
  DivineNameSpans spans,
  PluginDivineNamesDisplay names,
) {
  if (!names.filters) return line;
  var result = line;
  final marked = injectDivineNameMarkers(line, spans, lineIndex);
  if (!identical(marked, line)) {
    result = resolveDivineNameMarkers(
      marked,
      substituteOtherNames: names.substituteOtherNames,
      holyNameStyle: names.holyNameStyle,
    );
  }
  final style = names.holyNameStyle;
  if (style != null) result = replaceHolyNames(result, style: style);
  return withoutDivineNameJoiners(result);
}

/// טקסט נגזר בלי זהות שורה (תקציר חיפוש, כותרת, תווית עוגן): אין לו מופעי
/// מסד, ולכן רק שם הוי"ה מוחלף — כמו בתוצאות החיפוש של התוכנה.
String filterPluginDivineNamesText(
  String text,
  PluginDivineNamesDisplay names,
) {
  final style = names.holyNameStyle;
  return style == null ? text : replaceHolyNames(text, style: style);
}

/// נספח ל-payload של אירוע שמכיל טקסט מספר: הטקסט מחושב רק במסירה, לפי
/// [names] או, לתוסף שביקש `rawDivineNames`, כפי שנשמר. אינו ניתן לקידוד JSON.
final class PluginDivineNamesPayload {
  PluginDivineNamesPayload(this._names, this._apply);

  /// טקסט בלי זהות שורה (מפרש, PDF) — ראו [filterPluginDivineNamesText].
  factory PluginDivineNamesPayload.text(
    PluginDivineNamesDisplay Function() names,
  ) => PluginDivineNamesPayload(
    names,
    (payload, names) => {
      ...payload,
      if (payload['text'] case final String text)
        'text': filterPluginDivineNamesText(
          withoutDivineNameJoiners(text),
          names,
        ),
    },
  );

  static const String key = '__otzaria.divineNames';

  final PluginDivineNamesDisplay Function() _names;

  /// הצגת השמות לתוסף שלא ביקש את הטקסט כפי שנשמר; נקראת במסירה הראשונה.
  late final PluginDivineNamesDisplay names = _names();

  final Map<String, dynamic> Function(
    Map<String, dynamic> payload,
    PluginDivineNamesDisplay names,
  )
  _apply;

  Map<String, dynamic> attachTo(Map<String, dynamic> payload) => {
    ...payload,
    key: this,
  };

  /// [payload] כפי שתוסף מקבל אותו, בלי הנספח. [raw] — הטקסט כפי שנשמר.
  static Map<String, dynamic> select(
    Map<String, dynamic> payload, {
    bool raw = false,
  }) => resolve(payload, raw ? PluginDivineNamesDisplay.raw : null);

  /// כמו [select], עם [names] במקום הצגת השמות של הנספח.
  static Map<String, dynamic> resolve(
    Map<String, dynamic> payload,
    PluginDivineNamesDisplay? names,
  ) {
    final variants = payload[key];
    if (variants is! PluginDivineNamesPayload) return payload;
    final base = Map<String, dynamic>.of(payload)..remove(key);
    return variants._apply(base, names ?? variants.names);
  }
}

/// בקשת סינון של ספר שלם. עוברת ל-isolate, ולכן המופעים מגיעים כנתונים.
typedef PluginBookContentFilterRequest = ({
  String rawText,
  DivineNameSpans spans,
  PluginDivineNamesDisplay names,
  TextDisplayProfile? displayProfile,
});

/// תוכן הספר לתוסף: השמות לפי הבקשה, ועם [displayProfile] — גם שאר פרופיל
/// התצוגה, כמו `textReaderDisplay`.
String filterPluginBookContent(PluginBookContentFilterRequest request) {
  final profile = _contentProfile(request);
  final lines = request.rawText.split('\n');
  for (var i = 0; i < lines.length; i++) {
    lines[i] = _filterBookContentLine(lines[i], i, request, profile);
  }
  return lines.join('\n');
}

TextDisplayProfile? _contentProfile(PluginBookContentFilterRequest request) =>
    request.displayProfile == null
    ? null
    : request.names.applyTo(request.displayProfile!);

String _filterBookContentLine(
  String rawLine,
  int lineIndex,
  PluginBookContentFilterRequest request,
  TextDisplayProfile? profile,
) {
  final names = request.names;
  if (profile == null) {
    return filterPluginDivineNamesLine(
      rawLine,
      lineIndex,
      request.spans,
      names,
    );
  }
  final marked = names.filters
      ? injectDivineNameMarkers(rawLine, request.spans, lineIndex)
      : rawLine;
  var line = applyTextDisplayProfile(marked, profile);
  if (!identical(marked, rawLine)) {
    line = resolveDivineNameMarkers(
      line,
      substituteOtherNames: names.substituteOtherNames,
      holyNameStyle: names.holyNameStyle,
    );
  }
  return withoutDivineNameJoiners(line.replaceAll('\n', '<br>'));
}

/// אופסט [section] בתוכן המסונן [filtered], או -1. מחרוזת שמורה, או כותרת
/// שסוננה רק בשם הוי"ה, נמצאת בטקסט השמור ומתורגמת לאותה שורה ועמודה.
int locatePluginBookSection(
  ({
    PluginBookContentFilterRequest request,
    String filtered,
    String section,
  })
  input,
) {
  final (:request, :filtered, :section) = input;
  final direct = filtered.indexOf(section);
  final raw = request.rawText;
  var rawIndex = raw.indexOf(section);
  final style = request.names.holyNameStyle;
  if (rawIndex < 0 && style != null) {
    rawIndex = _rawIndexOfHolyNameForm(
      raw,
      replaceHolyNames(section, style: style),
      style,
    );
  }
  if (rawIndex < 0) return direct;
  var lineIndex = 0;
  var rawLineStart = 0;
  for (
    var i = raw.indexOf('\n');
    i >= 0 && i < rawIndex;
    i = raw.indexOf('\n', i + 1)
  ) {
    lineIndex++;
    rawLineStart = i + 1;
  }
  var filteredLineStart = 0;
  for (var i = 0; i < lineIndex; i++) {
    filteredLineStart = filtered.indexOf('\n', filteredLineStart) + 1;
    if (filteredLineStart == 0) return direct;
  }
  // חיתוך באמצע תג היה משנה את המרת הקידומת — חותכים לפני התג.
  var cut = rawIndex;
  if (rawIndex > rawLineStart) {
    final tagStart = raw.lastIndexOf('<', rawIndex - 1);
    if (tagStart >= rawLineStart &&
        raw.lastIndexOf('>', rawIndex - 1) < tagStart) {
      cut = tagStart;
    }
  }
  final mapped =
      filteredLineStart +
      _filterBookContentLine(
        raw.substring(rawLineStart, cut),
        lineIndex,
        request,
        _contentProfile(request),
      ).length;
  return direct >= 0 && direct < mapped ? direct : mapped;
}

/// מיקום [needle] בטקסט השמור [raw] כשהוא כתוב עם שם הוי"ה לפי [style].
int _rawIndexOfHolyNameForm(String raw, String needle, HolyNameStyle style) {
  final matches = findReplaceableHolyNames(raw);
  final index = (matches.isEmpty ? raw : replaceHolyNames(raw, style: style))
      .indexOf(needle);
  if (index < 0) return -1;
  var delta = 0;
  for (final match in matches) {
    final start = match.start + delta;
    if (index < start) break;
    final length = replaceHolyNames(match[0]!, style: style).length;
    if (index < start + length) return match.start;
    delta += length - (match.end - match.start);
  }
  return index - delta;
}
