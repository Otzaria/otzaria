import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

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
  bool? showSplitView,
  bool? removeNikud,
  bool? removePunctuation,
  bool? continuousReadingMode,
  bool? mikraTraditionalLayout,
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
      showSplitView == null &&
      continuousReadingMode == null &&
      mikraTraditionalLayout == null) {
    return;
  }

  final defaultFontSize = settingsBloc.state.fontSize;
  final defaultShowSplitView =
      Settings.getValue<bool>('key-splited-view') ?? true;
  final defaultContinuousReading =
      settingsBloc.state.defaultContinuousReadingMode;
  final defaultMikraLayout = settingsBloc.state.mikraTraditionalLayout;

  // עדכון אטומי: ה-load וה-merge מבוצעים בתוך תור הכתיבה כדי למנוע דריסה
  // הדדית עם שמירות מקבילות על אותו קובץ (רוחבי טורים, מפרשים).
  await TextBookPerBookSettings.mutate(state.book, (existingSettings) {
    double? newFontSize = existingSettings?.fontSize;
    bool? newCommentatorsBelow = existingSettings?.commentatorsBelow;
    bool? newContinuousReadingMode = existingSettings?.continuousReadingMode;
    bool? newMikraLayout = existingSettings?.mikraTraditionalLayout;

    if (fontSize != null) {
      newFontSize = (fontSize == defaultFontSize) ? null : fontSize;
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

    if (mikraTraditionalLayout != null) {
      newMikraLayout = (mikraTraditionalLayout == defaultMikraLayout)
          ? null
          : mikraTraditionalLayout;
    }

    return _withDisplayFields(
      existingSettings,
      fontSize: newFontSize,
      commentatorsBelow: newCommentatorsBelow,
      continuousReadingMode: newContinuousReadingMode,
      mikraTraditionalLayout: newMikraLayout,
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
      commentatorsBelow: existingSettings?.commentatorsBelow,
      continuousReadingMode: existingSettings?.continuousReadingMode,
      displayLayer: layer,
    );
  });
}

/// סימן ל-[_withDisplayFields]: השדה נשמר כפי שהוא בקובץ.
const Object _keepExisting = Object();

/// בונה את ההגדרות לשמירה; השדות הישנים removeNikud/removePunctuation/isTanach
/// אינם נכתבים עוד — הם חיים בתוך [displayLayer]. אם כל השדות null,
/// mutate ימחק את הקובץ.
TextBookPerBookSettings _withDisplayFields(
  TextBookPerBookSettings? existing, {
  required double? fontSize,
  required bool? commentatorsBelow,
  required bool? continuousReadingMode,
  Object? mikraTraditionalLayout = _keepExisting,
  required TextDisplayLayer? displayLayer,
}) {
  return TextBookPerBookSettings(
    fontSize: fontSize,
    commentatorsBelow: commentatorsBelow,
    displayLayer: (displayLayer == null || displayLayer.isEmpty)
        ? null
        : displayLayer,
    continuousReadingMode: continuousReadingMode,
    mikraTraditionalLayout: identical(mikraTraditionalLayout, _keepExisting)
        ? existing?.mikraTraditionalLayout
        : mikraTraditionalLayout as bool?,
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
      commentatorsBelow: existing.commentatorsBelow,
      continuousReadingMode: existing.continuousReadingMode,
      displayLayer: null,
    );
  });
}
