import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// שמירת שינוי בהגדרות התצוגה של הספר (גופן/ניקוד/פיסוק/פיצול/רצף) פר-ספר.
///
/// פעילה רק כש"שמירת התאמות לכל ספר" מופעלת בהגדרות. ערך השווה לברירת
/// המחדל הגלובלית נמחק מהקובץ כדי שהספר יירש שינויים עתידיים בברירת המחדל.
Future<void> savePerBookDisplaySettings(
  BuildContext context,
  TextBookLoaded state, {
  double? fontSize,
  bool? showSplitView,
  bool? removeNikud,
  bool? removePunctuation,
  bool? continuousReadingMode,
}) async {
  final settingsBloc = context.read<SettingsBloc>();
  if (!settingsBloc.state.enablePerBookSettings) {
    return;
  }

  final defaultFontSize = settingsBloc.state.fontSize;
  final defaultRemoveNikud = settingsBloc.state.defaultRemoveNikud;
  final defaultRemovePunctuation =
      settingsBloc.state.defaultRemovePunctuation && !state.isTanach;
  final defaultShowSplitView =
      Settings.getValue<bool>('key-splited-view') ?? true;
  final defaultContinuousReading =
      settingsBloc.state.defaultContinuousReadingMode;

  // עדכון אטומי: ה-load וה-merge מבוצעים בתוך תור הכתיבה כדי למנוע דריסה
  // הדדית עם שמירות מקבילות על אותו קובץ (רוחבי טורים, מפרשים).
  await TextBookPerBookSettings.mutate(state.book, (existingSettings) {
    double? newFontSize = existingSettings?.fontSize;
    bool? newCommentatorsBelow = existingSettings?.commentatorsBelow;
    bool? newRemoveNikud = existingSettings?.removeNikud;
    bool? newRemovePunctuation = existingSettings?.removePunctuation;
    bool? newContinuousReadingMode = existingSettings?.continuousReadingMode;

    if (fontSize != null) {
      newFontSize = (fontSize == defaultFontSize) ? null : fontSize;
    }

    if (showSplitView != null) {
      newCommentatorsBelow = (showSplitView == defaultShowSplitView)
          ? null
          : !showSplitView;
    }

    if (removeNikud != null) {
      newRemoveNikud = (removeNikud == defaultRemoveNikud) ? null : removeNikud;
    }

    if (removePunctuation != null) {
      newRemovePunctuation = (removePunctuation == defaultRemovePunctuation)
          ? null
          : removePunctuation;
    }
    // דגל התנ"ך נשמר רק כלוויין של override פיסוק — הניקוי התקופתי משתמש בו
    // לחישוב ברירת המחדל האפקטיבית של הספר (בתנ"ך היא תמיד false).
    final bool? newIsTanach = (newRemovePunctuation != null && state.isTanach)
        ? true
        : null;

    if (continuousReadingMode != null) {
      newContinuousReadingMode =
          (continuousReadingMode == defaultContinuousReading)
          ? null
          : continuousReadingMode;
    }

    // שדות שנשמרים בנפרד (רוחבי טורים, מפרשים) מועברים הלאה כדי לא להידרס.
    // אם כל השדות יתבררו כ-null, mutate ימחק את הקובץ.
    return TextBookPerBookSettings(
      fontSize: newFontSize,
      commentatorsBelow: newCommentatorsBelow,
      removeNikud: newRemoveNikud,
      removePunctuation: newRemovePunctuation,
      isTanach: newIsTanach,
      continuousReadingMode: newContinuousReadingMode,
      activeCommentators: existingSettings?.activeCommentators,
      pageShapeLeftWidth: existingSettings?.pageShapeLeftWidth,
      pageShapeRightWidth: existingSettings?.pageShapeRightWidth,
      pageShapeBottomHeight: existingSettings?.pageShapeBottomHeight,
      pageShapeBottomLeftWidth: existingSettings?.pageShapeBottomLeftWidth,
    );
  });
}
