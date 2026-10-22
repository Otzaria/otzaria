import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/html_slice.dart';

/// בוחר את תוכן ה-HTML המתאים ביותר לטקסט שנבחר: השורה המקורית כשהיא
/// נבחרה במלואה, אחרת חיתוך שלה לטווח הבחירה — כדי שגם בחירה חלקית
/// תישמר מעוצבת. נופל לטקסט פשוט רק כשהבחירה אינה נמצאת בשורה.
/// [divineNames] — מופעי השמות של [sourceContent] כשהם מוצגים מוחלפים, כדי
/// שהשורה תושווה לבחירה כפי שהיא על המסך.
String resolveHtmlTextForSelection({
  required String plainText,
  required int? selectedIndex,
  required List<String> sourceContent,
  DivineNameSpans? divineNames,
}) {
  if (selectedIndex == null ||
      selectedIndex < 0 ||
      selectedIndex >= sourceContent.length) {
    return plainText;
  }

  var originalData = sourceContent[selectedIndex];
  if (divineNames != null && !divineNames.isEmpty) {
    originalData = resolveDivineNameMarkers(
      injectDivineNameMarkers(originalData, divineNames, selectedIndex),
      substituteOtherNames: true,
    );
  }
  final plainTextCleaned = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
  final originalCleaned = originalData
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (plainTextCleaned == originalCleaned) {
    return originalData;
  }

  return sliceHtmlBySelection(
        html: originalData,
        selectedText: plainText,
      ) ??
      plainText;
}

/// מעתיק טקסט נבחר מספר טקסט תוך שמירה על כותרות ועיצוב.
///
/// [textBookState] הוא null בהעתקה ממשטח ללא `TextBookBloc` (חלונית ה-PDF);
/// אז [headerBookOverride] הוא מקור ספר הכותרת היחיד.
/// [removeNikud] — פעולת "העתק בלי ניקוד" (issue #851): ניקוד וטעמים
/// מוסרים מהעותק בלבד (כולל הכותרות וה-HTML), התצוגה לא משתנה.
/// [copyProfile] — פרופיל מלא ("העתק כ..." / קיצור דינמי) שמחליף את הדגלים.
/// [copyTarget] — בלי [copyProfile], ערוץ ההעתקה של היעד הזה חל על העותק.
/// [source] — הבחירה בלי ציוני המפרשים, לפרופיל שמסתיר אותם.
/// [plainTextOnly] — טקסט פשוט בלבד, בלי HTML מעוצב.
/// [protection] — הגבלת המו"ל של מקור הטקסט; ברירת המחדל היא של
/// [textBookState]. [segmentCount] — מספר שורות המקור שבבחירה, כשידוע.
/// [plainTextFilter] — עיבוד אחרון של הטקסט הנבחר (במקרא: הסרת {פ} ו-{ס}).
/// [sourceCitation] — ב«שם וכותרת»: ציון מקור לשורה שמחליף את «ספר, נתיב»
/// (בתורה: פרשה ועלייה); null לשורה — הנתיב הרגיל.
Future<void> copySelectedTextForBook({
  required String plainText,
  required int? selectedIndex,
  required List<String> sourceContent,
  required TextBookLoaded? textBookState,
  required SettingsState settingsState,
  required String fontFamily,
  required double fontSize,
  TextBook? headerBookOverride,
  List<String>? headerContentOverride,
  bool removeNikud = false,
  TextDisplayProfile? copyProfile,
  TextTarget? copyTarget,
  SourceSelection? source,
  bool plainTextOnly = false,
  BookProtection? protection,
  int? segmentCount,
  String Function(String text)? plainTextFilter,
  String? Function(int index)? sourceCitation,
}) async {
  if (!ensureCopyAllowed(
    protection ?? textBookState?.protection ?? BookProtection.none,
    segmentCount ?? countTextSegments(plainText),
  )) {
    return;
  }
  final copyContent = await buildSelectedTextCopy(
    plainText: plainText,
    selectedIndex: selectedIndex,
    sourceContent: sourceContent,
    textBookState: textBookState,
    settingsState: settingsState,
    headerBookOverride: headerBookOverride,
    headerContentOverride: headerContentOverride,
    removeNikud: removeNikud,
    copyProfile: copyProfile,
    copyTarget: copyTarget,
    source: source,
    plainTextFilter: plainTextFilter,
    sourceCitation: sourceCitation,
  );
  if (copyContent == null) return;
  final handler = debugSelectedTextCopyHandler;
  if (handler != null) return handler(copyContent);

  await CopyUtils.copyStyledToClipboard(
    plainText: copyContent.plainText,
    htmlText: copyContent.htmlText,
    fontFamily: fontFamily,
    fontSize: fontSize,
    plainTextOnly: plainTextOnly,
  );
}

/// בבדיקות: מקבל את מה ש-[copySelectedTextForBook] היה כותב ללוח.
@visibleForTesting
void Function(({String plainText, String htmlText}) content)?
debugSelectedTextCopyHandler;

/// התוכן ש-[copySelectedTextForBook] כותב ללוח; null כשלא נשאר מה להעתיק
/// (בחירה של ציון בלבד בערוץ שמסתיר ציונים) — כדי לא לדרוס את הלוח בריק.
Future<({String plainText, String htmlText})?> buildSelectedTextCopy({
  required String plainText,
  required int? selectedIndex,
  required List<String> sourceContent,
  required TextBookLoaded? textBookState,
  required SettingsState settingsState,
  TextBook? headerBookOverride,
  List<String>? headerContentOverride,
  bool removeNikud = false,
  TextDisplayProfile? copyProfile,
  TextTarget? copyTarget,
  SourceSelection? source,
  String Function(String text)? plainTextFilter,
  String? Function(int index)? sourceCitation,
}) async {
  var profile = copyProfile;
  if (profile == null && copyTarget != null && textBookState != null) {
    profile = textBookState.displayProfile(
      target: copyTarget,
      channel: TextChannel.copy,
    );
    if (removeNikud) {
      profile = profile.copyWith(
        nikud: MarkVisibility.hide,
        teamim: TeamimVisibility.hide,
      );
    }
  }
  if (profile != null && !profile.showAnchorMarkers) {
    plainText = SourceSelection.resolve(source, plainText, null).text;
    if (plainText.trim().isEmpty) return null;
  }
  if (plainTextFilter != null) {
    plainText = plainTextFilter(plainText);
    if (plainText.trim().isEmpty) return null;
  }

  final showsSubstitutedNames =
      textBookState != null &&
      identical(sourceContent, textBookState.content) &&
      textBookState.bodyDisplayProfile.substituteDivineNames;
  var htmlContentToUse = resolveHtmlTextForSelection(
    plainText: plainText,
    selectedIndex: selectedIndex,
    sourceContent: sourceContent,
    divineNames: showsSubstitutedNames ? textBookState.divineNames : null,
  );

  var finalPlainText = plainText;
  final headerBook = headerBookOverride ?? textBookState?.book;
  final citation =
      settingsState.copyWithHeaders == 'book_and_path' && headerBook != null
      ? sourceCitation?.call(selectedIndex ?? 0)
      : null;
  if (citation != null) {
    // ציון מקור אמיתי מחליף את «ספר, נתיב»; עיצוב הכותרת נשאר כבהגדרות.
    String withCitation(String text) => CopyUtils.formatTextWithHeaders(
      originalText: text,
      copyWithHeaders: 'book_name',
      copyHeaderFormat: settingsState.copyHeaderFormat,
      bookName: citation,
      currentPath: '',
    );
    finalPlainText = withCitation(plainText);
    htmlContentToUse = withCitation(htmlContentToUse);
  } else if (settingsState.copyWithHeaders != 'none' && headerBook != null) {
    final bookName = CopyUtils.extractBookName(headerBook);
    final currentIndex = selectedIndex ?? 0;
    final headerContent = headerContentOverride ?? sourceContent;
    final currentPath = await CopyUtils.extractCurrentPath(
      headerBook,
      currentIndex,
      bookContent: headerContent,
      isLineLoaded:
          identical(headerBook, textBookState?.book) &&
              identical(headerContent, textBookState?.content)
          ? textBookState?.isContentLineLoaded
          : null,
    );

    finalPlainText = CopyUtils.formatTextWithHeaders(
      originalText: plainText,
      copyWithHeaders: settingsState.copyWithHeaders,
      copyHeaderFormat: settingsState.copyHeaderFormat,
      bookName: bookName,
      currentPath: currentPath,
    );

    htmlContentToUse = CopyUtils.formatTextWithHeaders(
      originalText: htmlContentToUse,
      copyWithHeaders: settingsState.copyWithHeaders,
      copyHeaderFormat: settingsState.copyHeaderFormat,
      bookName: bookName,
      currentPath: currentPath,
    );
  }

  return CopyUtils.applyCopyPreferencesForClipboard(
    plainText: finalPlainText,
    htmlText: htmlContentToUse,
    replaceHolyNames: settingsState.replaceHolyNames,
    holyNameStyle: settingsState.holyNameStyle,
    removeNikud: removeNikud,
    profile: profile,
  );
}
