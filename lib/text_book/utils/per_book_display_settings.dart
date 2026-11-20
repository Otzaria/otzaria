import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

/// גודל גופן המפרשים בספר שב-[context]: מה שנשמר לספר, או הכללי (#2306).
double commentatorsFontSizeOf(BuildContext context, SettingsState settings) =>
    context.select((TextBookBloc bloc) {
      final state = bloc.state;
      return state is TextBookLoaded ? state.commentatorsFontSize : null;
    }) ??
    settings.commentatorsFontSize;

/// שמירת שינוי בהגדרות התצוגה של הספר (גופן/ניקוד/פיסוק/פיצול/רצף) פר-ספר.
///
/// פעילה רק כש"שמירת התאמות לכל ספר" מופעלת בהגדרות. ערך השווה לברירת
/// המחדל הגלובלית נמחק מהקובץ כדי שהספר יירש שינויים עתידיים בברירת המחדל.
/// [removeNikud]/[removePunctuation] נכתבים כטלאי על חריץ הגוף של התצוגה
/// הפעילה — ראה [savePerBookDisplayPatch].
Future<void> savePerBookDisplaySettings(
  BuildContext context,
  TextBookLoaded state, {
  double? fontSize,
  double? commentatorsFontSize,
  double? lineHeight,
  bool? showSplitView,
  bool? removeNikud,
  bool? removePunctuation,
  bool? continuousReadingMode,
}) async {
  final settingsBloc = context.read<SettingsBloc>();
  if (!settingsBloc.state.enablePerBookSettings) {
    return;
  }

  if (removeNikud != null || removePunctuation != null) {
    await savePerBookDisplayPatch(
      context,
      state,
      slot: TextDisplaySlot(
        target: TextTarget.body,
        view: state.activeView,
        channel: TextChannel.display,
      ),
      patch: TextDisplayPatch(
        nikud: removeNikud == null ? null : visibilityOf(removeNikud),
        punctuation: removePunctuation == null
            ? null
            : visibilityOf(removePunctuation),
      ),
    );
  }
  if (fontSize == null &&
      commentatorsFontSize == null &&
      lineHeight == null &&
      showSplitView == null &&
      continuousReadingMode == null) {
    return;
  }

  final defaultFontSize = settingsBloc.state.fontSize;
  final defaultShowSplitView =
      Settings.getValue<bool>('key-splited-view') ?? true;
  final defaultContinuousReading =
      settingsBloc.state.defaultContinuousReadingMode;

  // עדכון אטומי: ה-load וה-merge מבוצעים בתוך תור הכתיבה כדי למנוע דריסה
  // הדדית עם שמירות מקבילות על אותו קובץ (רוחבי טורים, מפרשים).
  await TextBookPerBookSettings.mutate(state.book, (existingSettings) {
    double? newFontSize = existingSettings?.fontSize;
    double? newCommentatorsFontSize = existingSettings?.commentatorsFontSize;
    double? newLineHeight = existingSettings?.lineHeight;
    bool? newCommentatorsBelow = existingSettings?.commentatorsBelow;
    bool? newContinuousReadingMode = existingSettings?.continuousReadingMode;

    if (fontSize != null) {
      newFontSize = (fontSize == defaultFontSize) ? null : fontSize;
    }
    if (commentatorsFontSize != null) {
      newCommentatorsFontSize =
          commentatorsFontSize == settingsBloc.state.commentatorsFontSize
          ? null
          : commentatorsFontSize;
    }
    if (lineHeight != null) {
      newLineHeight = lineHeight == settingsBloc.state.lineHeight
          ? null
          : lineHeight;
    }

    if (showSplitView != null) {
      newCommentatorsBelow = (showSplitView == defaultShowSplitView)
          ? null
          : !showSplitView;
    }

    if (continuousReadingMode != null) {
      newContinuousReadingMode =
          (continuousReadingMode == defaultContinuousReading)
          ? null
          : continuousReadingMode;
    }

    return _withDisplayFields(
      existingSettings,
      fontSize: newFontSize,
      commentatorsFontSize: newCommentatorsFontSize,
      lineHeight: newLineHeight,
      commentatorsBelow: newCommentatorsBelow,
      continuousReadingMode: newContinuousReadingMode,
      displayLayer: existingSettings?.effectiveDisplayLayer,
    );
  });
}

/// שומר טלאי תצוגה לחריץ [slot] בקובץ הספר. שדות ששווים למה שהמדיניות
/// הגלובלית הייתה נותנת לאותו חריץ נמחקים; השדות הישנים (`removeNikud`,
/// `removePunctuation`) מומרים לשכבה באותה הזדמנות.
///
/// פעיל רק כש"שמירת התאמות לכל ספר" מופעלת.
Future<void> savePerBookDisplayPatch(
  BuildContext context,
  TextBookLoaded state, {
  required TextDisplaySlot slot,
  required TextDisplayPatch patch,
}) async {
  final settingsBloc = context.read<SettingsBloc>();
  if (!settingsBloc.state.enablePerBookSettings) {
    return;
  }
  await persistPerBookDisplayPatch(
    book: state.book,
    isTanach: state.isTanach,
    policy: settingsBloc.state.textDisplayPolicy,
    slot: slot,
    patch: patch,
    checkEnabled: false,
  );
}

/// גרסה ללא BuildContext של [savePerBookDisplayPatch] — לבלוק ולקיצורים.
/// כש-[checkEnabled] פעיל בודקת בעצמה את "שמירת התאמות לכל ספר".
Future<void> persistPerBookDisplayPatch({
  required Book book,
  required bool isTanach,
  required TextDisplayPolicy policy,
  required TextDisplaySlot slot,
  required TextDisplayPatch patch,
  bool checkEnabled = true,
}) async {
  if (checkEnabled &&
      !(Settings.getValue<bool>(SettingsRepository.keyEnablePerBookSettings) ??
          false)) {
    return;
  }

  await TextBookPerBookSettings.mutate(book, (existingSettings) {
    final existingLayer =
        existingSettings?.effectiveDisplayLayer ?? TextDisplayLayer.empty;
    final merged = existingLayer.merged(slot, patch);
    // ההשוואה מול השכבה הפר-ספרית *בלי* החריץ הזה, כדי שערך שנורש מחריץ
    // אחר בקובץ (למשל הגוף) לא ייחשב סטייה כשהוא שווה לו.
    final base = TextDisplayResolver.resolve(
      slot: slot,
      layers: [
        merged.without(slot),
        ...policy.layersFor(isTanach: isTanach),
      ],
    );
    final pruned = merged.patchFor(slot).pruneAgainst(base);
    final layer = pruned.isEmpty
        ? merged.without(slot)
        : merged.withSlot(slot, pruned);

    return _withDisplayFields(
      existingSettings,
      fontSize: existingSettings?.fontSize,
      commentatorsFontSize: existingSettings?.commentatorsFontSize,
      lineHeight: existingSettings?.lineHeight,
      commentatorsBelow: existingSettings?.commentatorsBelow,
      continuousReadingMode: existingSettings?.continuousReadingMode,
      displayLayer: layer,
    );
  });
}

/// בונה את ההגדרות לשמירה; השדות הישנים removeNikud/removePunctuation/isTanach
/// אינם נכתבים עוד — הם חיים בתוך [displayLayer]. אם כל השדות null,
/// mutate ימחק את הקובץ.
TextBookPerBookSettings _withDisplayFields(
  TextBookPerBookSettings? existing, {
  required double? fontSize,
  required double? commentatorsFontSize,
  required double? lineHeight,
  required bool? commentatorsBelow,
  required bool? continuousReadingMode,
  required TextDisplayLayer? displayLayer,
}) {
  return TextBookPerBookSettings(
    fontSize: fontSize,
    commentatorsFontSize: commentatorsFontSize,
    lineHeight: lineHeight,
    commentatorsBelow: commentatorsBelow,
    displayLayer: (displayLayer == null || displayLayer.isEmpty)
        ? null
        : displayLayer,
    continuousReadingMode: continuousReadingMode,
    activeCommentators: existing?.activeCommentators,
    pageShapeLeftWidth: existing?.pageShapeLeftWidth,
    pageShapeRightWidth: existing?.pageShapeRightWidth,
    pageShapeBottomHeight: existing?.pageShapeBottomHeight,
    pageShapeBottomLeftWidth: existing?.pageShapeBottomLeftWidth,
  );
}

/// מוחק את שכבת התצוגה של הספר (כל החריצים). שאר ההגדרות הפר-ספריות נשמרות.
Future<void> clearPerBookDisplayLayer(Book book) async {
  final enabled =
      Settings.getValue<bool>(SettingsRepository.keyEnablePerBookSettings) ??
      false;
  if (!enabled) return;
  await TextBookPerBookSettings.mutate(book, (existing) {
    if (existing == null) return null;
    return _withDisplayFields(
      existing,
      fontSize: existing.fontSize,
      commentatorsFontSize: existing.commentatorsFontSize,
      lineHeight: existing.lineHeight,
      commentatorsBelow: existing.commentatorsBelow,
      continuousReadingMode: existing.continuousReadingMode,
      displayLayer: null,
    );
  });
}
