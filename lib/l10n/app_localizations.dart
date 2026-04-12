import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he')
  ];

  /// No description provided for @appTitle.
  ///
  /// In he, this message translates to:
  /// **'אוצריא'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In he, this message translates to:
  /// **'הגדרות'**
  String get settingsTitle;

  /// No description provided for @settingsBack.
  ///
  /// In he, this message translates to:
  /// **'חזור (Backspace)'**
  String get settingsBack;

  /// No description provided for @settingsTabDesign.
  ///
  /// In he, this message translates to:
  /// **'מראה'**
  String get settingsTabDesign;

  /// No description provided for @settingsTabText.
  ///
  /// In he, this message translates to:
  /// **'כתב'**
  String get settingsTabText;

  /// No description provided for @settingsTabLibrary.
  ///
  /// In he, this message translates to:
  /// **'ספריה'**
  String get settingsTabLibrary;

  /// No description provided for @settingsTabTools.
  ///
  /// In he, this message translates to:
  /// **'כלים'**
  String get settingsTabTools;

  /// No description provided for @settingsTabShortcuts.
  ///
  /// In he, this message translates to:
  /// **'קיצורים'**
  String get settingsTabShortcuts;

  /// No description provided for @settingsTabSystem.
  ///
  /// In he, this message translates to:
  /// **'מערכת'**
  String get settingsTabSystem;

  /// No description provided for @settingsTabAbout.
  ///
  /// In he, this message translates to:
  /// **'אודות'**
  String get settingsTabAbout;

  /// No description provided for @settingsGroupDisplayContent.
  ///
  /// In he, this message translates to:
  /// **'תצוגה ותוכן'**
  String get settingsGroupDisplayContent;

  /// No description provided for @settingsGroupTools.
  ///
  /// In he, this message translates to:
  /// **'כלים'**
  String get settingsGroupTools;

  /// No description provided for @settingsGroupSystem.
  ///
  /// In he, this message translates to:
  /// **'מערכת'**
  String get settingsGroupSystem;

  /// No description provided for @settingsLanguageCardTitle.
  ///
  /// In he, this message translates to:
  /// **'שפה'**
  String get settingsLanguageCardTitle;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In he, this message translates to:
  /// **'שפת ממשק'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSubtitleHe.
  ///
  /// In he, this message translates to:
  /// **'הממשק מוצג בעברית'**
  String get settingsLanguageSubtitleHe;

  /// No description provided for @settingsLanguageSubtitleEn.
  ///
  /// In he, this message translates to:
  /// **'הממשק מוצג באנגלית'**
  String get settingsLanguageSubtitleEn;

  /// No description provided for @settingsLanguageHebrew.
  ///
  /// In he, this message translates to:
  /// **'עברית'**
  String get settingsLanguageHebrew;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In he, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageRestartHint.
  ///
  /// In he, this message translates to:
  /// **'חלק מהמסכים יתעדכנו מיד, וטקסטים שעדיין לא הועברו לקובץ התרגום יישארו בעברית.'**
  String get settingsLanguageRestartHint;

  /// No description provided for @literalTranslation001.
  ///
  /// In he, this message translates to:
  /// **'הגדרות'**
  String get literalTranslation001;

  /// No description provided for @literalTranslation002.
  ///
  /// In he, this message translates to:
  /// **'מראה'**
  String get literalTranslation002;

  /// No description provided for @literalTranslation003.
  ///
  /// In he, this message translates to:
  /// **'כתב'**
  String get literalTranslation003;

  /// No description provided for @literalTranslation004.
  ///
  /// In he, this message translates to:
  /// **'ספריה'**
  String get literalTranslation004;

  /// No description provided for @literalTranslation005.
  ///
  /// In he, this message translates to:
  /// **'כלים'**
  String get literalTranslation005;

  /// No description provided for @literalTranslation006.
  ///
  /// In he, this message translates to:
  /// **'קיצורים'**
  String get literalTranslation006;

  /// No description provided for @literalTranslation007.
  ///
  /// In he, this message translates to:
  /// **'מערכת'**
  String get literalTranslation007;

  /// No description provided for @literalTranslation008.
  ///
  /// In he, this message translates to:
  /// **'אודות'**
  String get literalTranslation008;

  /// No description provided for @literalTranslation009.
  ///
  /// In he, this message translates to:
  /// **'תצוגה ותוכן'**
  String get literalTranslation009;

  /// No description provided for @literalTranslation010.
  ///
  /// In he, this message translates to:
  /// **'חזור (Backspace)'**
  String get literalTranslation010;

  /// No description provided for @literalTranslation011.
  ///
  /// In he, this message translates to:
  /// **'תצוגה'**
  String get literalTranslation011;

  /// No description provided for @literalTranslation012.
  ///
  /// In he, this message translates to:
  /// **'מסך מלא'**
  String get literalTranslation012;

  /// No description provided for @literalTranslation013.
  ///
  /// In he, this message translates to:
  /// **'החלף מצב מסך מלא'**
  String get literalTranslation013;

  /// No description provided for @literalTranslation014.
  ///
  /// In he, this message translates to:
  /// **'ערכת נושא'**
  String get literalTranslation014;

  /// No description provided for @literalTranslation015.
  ///
  /// In he, this message translates to:
  /// **'מעקב אחר צבע המערכת'**
  String get literalTranslation015;

  /// No description provided for @literalTranslation016.
  ///
  /// In he, this message translates to:
  /// **'מופעל'**
  String get literalTranslation016;

  /// No description provided for @literalTranslation017.
  ///
  /// In he, this message translates to:
  /// **'לא מופעל'**
  String get literalTranslation017;

  /// No description provided for @literalTranslation018.
  ///
  /// In he, this message translates to:
  /// **'מצב כהה'**
  String get literalTranslation018;

  /// No description provided for @literalTranslation019.
  ///
  /// In he, this message translates to:
  /// **'צבע בסיס'**
  String get literalTranslation019;

  /// No description provided for @literalTranslation020.
  ///
  /// In he, this message translates to:
  /// **'כרטיסיות הספרים'**
  String get literalTranslation020;

  /// No description provided for @literalTranslation021.
  ///
  /// In he, this message translates to:
  /// **'תפריטים קומפקטיים'**
  String get literalTranslation021;

  /// No description provided for @literalTranslation022.
  ///
  /// In he, this message translates to:
  /// **'התפריטים יוצגו בצפיפות עבודה בסגנון Chrome'**
  String get literalTranslation022;

  /// No description provided for @literalTranslation023.
  ///
  /// In he, this message translates to:
  /// **'התפריטים יוצגו במרווח נוח ובגרסה הרגילה'**
  String get literalTranslation023;

  /// No description provided for @literalTranslation024.
  ///
  /// In he, this message translates to:
  /// **'הצגת כרטיסיות בימין'**
  String get literalTranslation024;

  /// No description provided for @literalTranslation025.
  ///
  /// In he, this message translates to:
  /// **'הכרטיסיות יהיו בצד ימין'**
  String get literalTranslation025;

  /// No description provided for @literalTranslation026.
  ///
  /// In he, this message translates to:
  /// **'הכרטיסיות יהיו במרכז החלון'**
  String get literalTranslation026;

  /// No description provided for @literalTranslation027.
  ///
  /// In he, this message translates to:
  /// **'חלוניות עזר'**
  String get literalTranslation027;

  /// No description provided for @literalTranslation028.
  ///
  /// In he, this message translates to:
  /// **'חלונית ניווט בין כותרות'**
  String get literalTranslation028;

  /// No description provided for @literalTranslation029.
  ///
  /// In he, this message translates to:
  /// **'החלונית תוצג באופן קבוע'**
  String get literalTranslation029;

  /// No description provided for @literalTranslation030.
  ///
  /// In he, this message translates to:
  /// **'החלונית תוצג בפתיחת ספר ותיסגר בעת גלילה'**
  String get literalTranslation030;

  /// No description provided for @literalTranslation031.
  ///
  /// In he, this message translates to:
  /// **'החלונית לא תוצג אוטומטית עם פתיחת הספר'**
  String get literalTranslation031;

  /// No description provided for @literalTranslation032.
  ///
  /// In he, this message translates to:
  /// **'הצגה'**
  String get literalTranslation032;

  /// No description provided for @literalTranslation033.
  ///
  /// In he, this message translates to:
  /// **'אוטומטי'**
  String get literalTranslation033;

  /// No description provided for @literalTranslation034.
  ///
  /// In he, this message translates to:
  /// **'הסתרה'**
  String get literalTranslation034;

  /// No description provided for @literalTranslation035.
  ///
  /// In he, this message translates to:
  /// **'הסתרת הערות אישיות'**
  String get literalTranslation035;

  /// No description provided for @literalTranslation036.
  ///
  /// In he, this message translates to:
  /// **'רשימות ההערות ייפתחו במצב סגור'**
  String get literalTranslation036;

  /// No description provided for @literalTranslation037.
  ///
  /// In he, this message translates to:
  /// **'רשימות ההערות ייפתחו במצב פתוח'**
  String get literalTranslation037;

  /// No description provided for @literalTranslation038.
  ///
  /// In he, this message translates to:
  /// **'הצגת המפרשים בחלונית בצד'**
  String get literalTranslation038;

  /// No description provided for @literalTranslation039.
  ///
  /// In he, this message translates to:
  /// **'המפרשים יוצגו בחלונית מפוצלת'**
  String get literalTranslation039;

  /// No description provided for @literalTranslation040.
  ///
  /// In he, this message translates to:
  /// **'המפרשים יוצגו בתוך הטקסט'**
  String get literalTranslation040;

  /// No description provided for @literalTranslation041.
  ///
  /// In he, this message translates to:
  /// **'הגדרות גופן ועיצוב'**
  String get literalTranslation041;

  /// No description provided for @literalTranslation042.
  ///
  /// In he, this message translates to:
  /// **'גודל גופן הספר'**
  String get literalTranslation042;

  /// No description provided for @literalTranslation043.
  ///
  /// In he, this message translates to:
  /// **'גופן טקסט'**
  String get literalTranslation043;

  /// No description provided for @literalTranslation044.
  ///
  /// In he, this message translates to:
  /// **'גודל גופן מפרשים'**
  String get literalTranslation044;

  /// No description provided for @literalTranslation045.
  ///
  /// In he, this message translates to:
  /// **'גופן מפרשים'**
  String get literalTranslation045;

  /// No description provided for @literalTranslation046.
  ///
  /// In he, this message translates to:
  /// **'מרווח בין שורות'**
  String get literalTranslation046;

  /// No description provided for @literalTranslation047.
  ///
  /// In he, this message translates to:
  /// **'כתרי אותיות'**
  String get literalTranslation047;

  /// No description provided for @literalTranslation048.
  ///
  /// In he, this message translates to:
  /// **'הצגת הניקוד'**
  String get literalTranslation048;

  /// No description provided for @literalTranslation049.
  ///
  /// In he, this message translates to:
  /// **'הניקוד יוצג בכל הספרים'**
  String get literalTranslation049;

  /// No description provided for @literalTranslation050.
  ///
  /// In he, this message translates to:
  /// **'הניקוד יוצג בספרי התנ\"ך בלבד'**
  String get literalTranslation050;

  /// No description provided for @literalTranslation051.
  ///
  /// In he, this message translates to:
  /// **'הניקוד לא יוצג בכלל'**
  String get literalTranslation051;

  /// No description provided for @literalTranslation052.
  ///
  /// In he, this message translates to:
  /// **'הצג תמיד'**
  String get literalTranslation052;

  /// No description provided for @literalTranslation053.
  ///
  /// In he, this message translates to:
  /// **'הצג בתנ\"ך'**
  String get literalTranslation053;

  /// No description provided for @literalTranslation054.
  ///
  /// In he, this message translates to:
  /// **'אל תציג'**
  String get literalTranslation054;

  /// No description provided for @literalTranslation055.
  ///
  /// In he, this message translates to:
  /// **'הצגת שם הקודש'**
  String get literalTranslation055;

  /// No description provided for @literalTranslation056.
  ///
  /// In he, this message translates to:
  /// **'השם הקדוש יוצג'**
  String get literalTranslation056;

  /// No description provided for @literalTranslation057.
  ///
  /// In he, this message translates to:
  /// **'השם הקדוש לא יוצג מפני קדושתו'**
  String get literalTranslation057;

  /// No description provided for @literalTranslation058.
  ///
  /// In he, this message translates to:
  /// **'הצגת טעמי המקרא'**
  String get literalTranslation058;

  /// No description provided for @literalTranslation059.
  ///
  /// In he, this message translates to:
  /// **'המקרא יוצג עם טעמים'**
  String get literalTranslation059;

  /// No description provided for @literalTranslation060.
  ///
  /// In he, this message translates to:
  /// **'המקרא יוצג ללא טעמים'**
  String get literalTranslation060;

  /// No description provided for @literalTranslation061.
  ///
  /// In he, this message translates to:
  /// **'הגדרות העתקה'**
  String get literalTranslation061;

  /// No description provided for @literalTranslation062.
  ///
  /// In he, this message translates to:
  /// **'העתקה עם כותרות'**
  String get literalTranslation062;

  /// No description provided for @literalTranslation063.
  ///
  /// In he, this message translates to:
  /// **'ללא'**
  String get literalTranslation063;

  /// No description provided for @literalTranslation064.
  ///
  /// In he, this message translates to:
  /// **'שם הספר בלבד'**
  String get literalTranslation064;

  /// No description provided for @literalTranslation065.
  ///
  /// In he, this message translates to:
  /// **'שם הספר+נתיב'**
  String get literalTranslation065;

  /// No description provided for @literalTranslation066.
  ///
  /// In he, this message translates to:
  /// **'עיצוב העתקה'**
  String get literalTranslation066;

  /// No description provided for @literalTranslation067.
  ///
  /// In he, this message translates to:
  /// **'אותה שורה אחרי (עם סוגריים)'**
  String get literalTranslation067;

  /// No description provided for @literalTranslation068.
  ///
  /// In he, this message translates to:
  /// **'אותה שורה אחרי (בלי סוגריים)'**
  String get literalTranslation068;

  /// No description provided for @literalTranslation069.
  ///
  /// In he, this message translates to:
  /// **'אותה שורה לפני (עם סוגריים)'**
  String get literalTranslation069;

  /// No description provided for @literalTranslation070.
  ///
  /// In he, this message translates to:
  /// **'אותה שורה לפני (בלי סוגריים)'**
  String get literalTranslation070;

  /// No description provided for @literalTranslation071.
  ///
  /// In he, this message translates to:
  /// **'פסקה נפרדת אחרי'**
  String get literalTranslation071;

  /// No description provided for @literalTranslation072.
  ///
  /// In he, this message translates to:
  /// **'פסקה נפרדת לפני'**
  String get literalTranslation072;

  /// No description provided for @literalTranslation073.
  ///
  /// In he, this message translates to:
  /// **'הגדרות לפי ספר'**
  String get literalTranslation073;

  /// No description provided for @literalTranslation074.
  ///
  /// In he, this message translates to:
  /// **'שמירת התאמות לכל ספר בנפרד'**
  String get literalTranslation074;

  /// No description provided for @literalTranslation075.
  ///
  /// In he, this message translates to:
  /// **'שינויים בסרגל הלחצנים יישמרו לכל ספר בנפרד'**
  String get literalTranslation075;

  /// No description provided for @literalTranslation076.
  ///
  /// In he, this message translates to:
  /// **'כל הספרים ישתמשו בהגדרות הכלליות'**
  String get literalTranslation076;

  /// No description provided for @literalTranslation077.
  ///
  /// In he, this message translates to:
  /// **'אפס את כל הגדרות אלו, בכל הספרים'**
  String get literalTranslation077;

  /// No description provided for @literalTranslation078.
  ///
  /// In he, this message translates to:
  /// **'מלא'**
  String get literalTranslation078;

  /// No description provided for @literalTranslation079.
  ///
  /// In he, this message translates to:
  /// **'רוחב הטקסט'**
  String get literalTranslation079;

  /// No description provided for @literalTranslation080.
  ///
  /// In he, this message translates to:
  /// **'הטקסט ימלא את כל הרוחב הזמין'**
  String get literalTranslation080;

  /// No description provided for @literalTranslation081.
  ///
  /// In he, this message translates to:
  /// **'הטקסט יהיה צר יותר ומרוכז במסך'**
  String get literalTranslation081;

  /// No description provided for @literalTranslation082.
  ///
  /// In he, this message translates to:
  /// **'תצוגת ספרייה'**
  String get literalTranslation082;

  /// No description provided for @literalTranslation083.
  ///
  /// In he, this message translates to:
  /// **'סוג תצוגה'**
  String get literalTranslation083;

  /// No description provided for @literalTranslation084.
  ///
  /// In he, this message translates to:
  /// **'רשת'**
  String get literalTranslation084;

  /// No description provided for @literalTranslation085.
  ///
  /// In he, this message translates to:
  /// **'רשימה'**
  String get literalTranslation085;

  /// No description provided for @literalTranslation086.
  ///
  /// In he, this message translates to:
  /// **'תצוגת רשת'**
  String get literalTranslation086;

  /// No description provided for @literalTranslation087.
  ///
  /// In he, this message translates to:
  /// **'תצוגת רשימה (עץ מתרחב)'**
  String get literalTranslation087;

  /// No description provided for @literalTranslation088.
  ///
  /// In he, this message translates to:
  /// **'הצג תצוגה מקדימה'**
  String get literalTranslation088;

  /// No description provided for @literalTranslation089.
  ///
  /// In he, this message translates to:
  /// **'תצוגה מקדימה מוצגת'**
  String get literalTranslation089;

  /// No description provided for @literalTranslation090.
  ///
  /// In he, this message translates to:
  /// **'תצוגה מקדימה מוסתרת'**
  String get literalTranslation090;

  /// No description provided for @literalTranslation091.
  ///
  /// In he, this message translates to:
  /// **'ספרים נוספים'**
  String get literalTranslation091;

  /// No description provided for @literalTranslation092.
  ///
  /// In he, this message translates to:
  /// **'הצגת ספרים מאתרים חיצוניים'**
  String get literalTranslation092;

  /// No description provided for @literalTranslation093.
  ///
  /// In he, this message translates to:
  /// **'יוצגו גם ספרים מאתרים חיצוניים'**
  String get literalTranslation093;

  /// No description provided for @literalTranslation094.
  ///
  /// In he, this message translates to:
  /// **'יוצגו רק ספרים מספריית אוצריא'**
  String get literalTranslation094;

  /// No description provided for @literalTranslation095.
  ///
  /// In he, this message translates to:
  /// **'הצג ספרים מאוצר החכמה'**
  String get literalTranslation095;

  /// No description provided for @literalTranslation096.
  ///
  /// In he, this message translates to:
  /// **'ספרים מאתר אוצר החכמה'**
  String get literalTranslation096;

  /// No description provided for @literalTranslation097.
  ///
  /// In he, this message translates to:
  /// **'הצג ספרים מהיברובוקס'**
  String get literalTranslation097;

  /// No description provided for @literalTranslation098.
  ///
  /// In he, this message translates to:
  /// **'ספרים מאתר HebrewBooks'**
  String get literalTranslation098;

  /// No description provided for @literalTranslation099.
  ///
  /// In he, this message translates to:
  /// **'סנכרון קטלוגים אוטומטי'**
  String get literalTranslation099;

  /// No description provided for @literalTranslation100.
  ///
  /// In he, this message translates to:
  /// **'עדכן קטלוגים חיצוניים אוטומטית'**
  String get literalTranslation100;

  /// No description provided for @literalTranslation101.
  ///
  /// In he, this message translates to:
  /// **'מאגר הספרים'**
  String get literalTranslation101;

  /// No description provided for @literalTranslation102.
  ///
  /// In he, this message translates to:
  /// **'תיקיות מותאמות אישית'**
  String get literalTranslation102;

  /// No description provided for @literalTranslation103.
  ///
  /// In he, this message translates to:
  /// **'חיפוש ואינדקס'**
  String get literalTranslation103;

  /// No description provided for @literalTranslation104.
  ///
  /// In he, this message translates to:
  /// **'עדכון אינדקס אוטומטי'**
  String get literalTranslation104;

  /// No description provided for @literalTranslation105.
  ///
  /// In he, this message translates to:
  /// **'אינדקס החיפוש יתעדכן אוטומטית'**
  String get literalTranslation105;

  /// No description provided for @literalTranslation106.
  ///
  /// In he, this message translates to:
  /// **'אינדקס החיפוש לא יתעדכן אוטומטית'**
  String get literalTranslation106;

  /// No description provided for @literalTranslation107.
  ///
  /// In he, this message translates to:
  /// **'לא קיימת ספרייה לאינדוקס'**
  String get literalTranslation107;

  /// No description provided for @literalTranslation108.
  ///
  /// In he, this message translates to:
  /// **'הספרייה ריקה – אין ספרים לאינדוקס'**
  String get literalTranslation108;

  /// No description provided for @literalTranslation109.
  ///
  /// In he, this message translates to:
  /// **'האינדקס מעודכן'**
  String get literalTranslation109;

  /// No description provided for @literalTranslation110.
  ///
  /// In he, this message translates to:
  /// **'האינדקס לא מעודכן'**
  String get literalTranslation110;

  /// No description provided for @literalTranslation111.
  ///
  /// In he, this message translates to:
  /// **'אינדקס חיפוש'**
  String get literalTranslation111;

  /// No description provided for @literalTranslation112.
  ///
  /// In he, this message translates to:
  /// **'עצור'**
  String get literalTranslation112;

  /// No description provided for @literalTranslation113.
  ///
  /// In he, this message translates to:
  /// **'איפוס'**
  String get literalTranslation113;

  /// No description provided for @literalTranslation114.
  ///
  /// In he, this message translates to:
  /// **'עדכן'**
  String get literalTranslation114;

  /// No description provided for @literalTranslation115.
  ///
  /// In he, this message translates to:
  /// **'עדכוני מערכת'**
  String get literalTranslation115;

  /// No description provided for @literalTranslation116.
  ///
  /// In he, this message translates to:
  /// **'סינכרון ומצב רשת'**
  String get literalTranslation116;

  /// No description provided for @literalTranslation117.
  ///
  /// In he, this message translates to:
  /// **'התוכנה מנותקת לגמרי מהרשת'**
  String get literalTranslation117;

  /// No description provided for @literalTranslation118.
  ///
  /// In he, this message translates to:
  /// **'התוכנה יכולה להתחבר לרשת'**
  String get literalTranslation118;

  /// No description provided for @literalTranslation119.
  ///
  /// In he, this message translates to:
  /// **'מקוון'**
  String get literalTranslation119;

  /// No description provided for @literalTranslation120.
  ///
  /// In he, this message translates to:
  /// **'מנותק'**
  String get literalTranslation120;

  /// No description provided for @literalTranslation121.
  ///
  /// In he, this message translates to:
  /// **'עדכוני תוכנה וספרים'**
  String get literalTranslation121;

  /// No description provided for @literalTranslation122.
  ///
  /// In he, this message translates to:
  /// **'מושבת במצב מנותק'**
  String get literalTranslation122;

  /// No description provided for @literalTranslation123.
  ///
  /// In he, this message translates to:
  /// **'סינכרון הספרייה באופן אוטומטי'**
  String get literalTranslation123;

  /// No description provided for @literalTranslation124.
  ///
  /// In he, this message translates to:
  /// **'מסד הנתונים של הספרייה יתעדכן אוטומטית'**
  String get literalTranslation124;

  /// No description provided for @literalTranslation125.
  ///
  /// In he, this message translates to:
  /// **'סינכרון הספרייה מושבת'**
  String get literalTranslation125;

  /// No description provided for @literalTranslation126.
  ///
  /// In he, this message translates to:
  /// **'עדכון לגרסאות מפתחים'**
  String get literalTranslation126;

  /// No description provided for @literalTranslation127.
  ///
  /// In he, this message translates to:
  /// **'קבלת עדכונים על גרסאות בדיקה — ייתכנו באגים'**
  String get literalTranslation127;

  /// No description provided for @literalTranslation128.
  ///
  /// In he, this message translates to:
  /// **'קבלת עדכונים על גרסאות יציבות בלבד'**
  String get literalTranslation128;

  /// No description provided for @literalTranslation129.
  ///
  /// In he, this message translates to:
  /// **'דיווחי טעויות'**
  String get literalTranslation129;

  /// No description provided for @literalTranslation130.
  ///
  /// In he, this message translates to:
  /// **'שליחה ישירה לצוות אוצריא, כולל תור אוטומטי במצב אופליין.'**
  String get literalTranslation130;

  /// No description provided for @literalTranslation131.
  ///
  /// In he, this message translates to:
  /// **'כתובת מייל לזיהוי'**
  String get literalTranslation131;

  /// No description provided for @literalTranslation132.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא הוגדרה כתובת זיהוי'**
  String get literalTranslation132;

  /// No description provided for @literalTranslation133.
  ///
  /// In he, this message translates to:
  /// **'נקה'**
  String get literalTranslation133;

  /// No description provided for @literalTranslation134.
  ///
  /// In he, this message translates to:
  /// **'הגדר'**
  String get literalTranslation134;

  /// No description provided for @literalTranslation135.
  ///
  /// In he, this message translates to:
  /// **'ערוך'**
  String get literalTranslation135;

  /// No description provided for @literalTranslation136.
  ///
  /// In he, this message translates to:
  /// **'שמירת דיווחים אוטומטית כשאין חיבור'**
  String get literalTranslation136;

  /// No description provided for @literalTranslation137.
  ///
  /// In he, this message translates to:
  /// **'ניהול דיווחים שמורים'**
  String get literalTranslation137;

  /// No description provided for @literalTranslation138.
  ///
  /// In he, this message translates to:
  /// **'אין כרגע דיווחים שמורים בתור'**
  String get literalTranslation138;

  /// No description provided for @literalTranslation139.
  ///
  /// In he, this message translates to:
  /// **'שלח עכשיו'**
  String get literalTranslation139;

  /// No description provided for @literalTranslation140.
  ///
  /// In he, this message translates to:
  /// **'נקה דיווחים'**
  String get literalTranslation140;

  /// No description provided for @literalTranslation141.
  ///
  /// In he, this message translates to:
  /// **'הורד לשליחה במחשב מחובר'**
  String get literalTranslation141;

  /// No description provided for @literalTranslation142.
  ///
  /// In he, this message translates to:
  /// **'מערכת אוצריא'**
  String get literalTranslation142;

  /// No description provided for @literalTranslation143.
  ///
  /// In he, this message translates to:
  /// **'גרסת תוכנה'**
  String get literalTranslation143;

  /// No description provided for @literalTranslation144.
  ///
  /// In he, this message translates to:
  /// **'טוען...'**
  String get literalTranslation144;

  /// No description provided for @literalTranslation145.
  ///
  /// In he, this message translates to:
  /// **'יומן שינויים'**
  String get literalTranslation145;

  /// No description provided for @literalTranslation146.
  ///
  /// In he, this message translates to:
  /// **'גרסת ספרייה'**
  String get literalTranslation146;

  /// No description provided for @literalTranslation147.
  ///
  /// In he, this message translates to:
  /// **'מספר ספרים'**
  String get literalTranslation147;

  /// No description provided for @literalTranslation148.
  ///
  /// In he, this message translates to:
  /// **'לא ידוע'**
  String get literalTranslation148;

  /// No description provided for @literalTranslation149.
  ///
  /// In he, this message translates to:
  /// **'תורמים'**
  String get literalTranslation149;

  /// No description provided for @literalTranslation150.
  ///
  /// In he, this message translates to:
  /// **'מתקדם'**
  String get literalTranslation150;

  /// No description provided for @literalTranslation151.
  ///
  /// In he, this message translates to:
  /// **'גיבוי אוטומטי'**
  String get literalTranslation151;

  /// No description provided for @literalTranslation152.
  ///
  /// In he, this message translates to:
  /// **'שבועי'**
  String get literalTranslation152;

  /// No description provided for @literalTranslation153.
  ///
  /// In he, this message translates to:
  /// **'חודשי'**
  String get literalTranslation153;

  /// No description provided for @literalTranslation154.
  ///
  /// In he, this message translates to:
  /// **'מצב גיבוי'**
  String get literalTranslation154;

  /// No description provided for @literalTranslation155.
  ///
  /// In he, this message translates to:
  /// **'גבה הכל'**
  String get literalTranslation155;

  /// No description provided for @literalTranslation156.
  ///
  /// In he, this message translates to:
  /// **'מותאם אישית'**
  String get literalTranslation156;

  /// No description provided for @literalTranslation157.
  ///
  /// In he, this message translates to:
  /// **'כולל את כלל הגדרות התוכנה'**
  String get literalTranslation157;

  /// No description provided for @literalTranslation158.
  ///
  /// In he, this message translates to:
  /// **'סימניות'**
  String get literalTranslation158;

  /// No description provided for @literalTranslation159.
  ///
  /// In he, this message translates to:
  /// **'כל הסימניות שנשמרו'**
  String get literalTranslation159;

  /// No description provided for @literalTranslation160.
  ///
  /// In he, this message translates to:
  /// **'היסטוריה'**
  String get literalTranslation160;

  /// No description provided for @literalTranslation161.
  ///
  /// In he, this message translates to:
  /// **'היסטוריית הלימוד'**
  String get literalTranslation161;

  /// No description provided for @literalTranslation162.
  ///
  /// In he, this message translates to:
  /// **'הערות אישיות'**
  String get literalTranslation162;

  /// No description provided for @literalTranslation163.
  ///
  /// In he, this message translates to:
  /// **'כל ההערות האישיות שלך'**
  String get literalTranslation163;

  /// No description provided for @literalTranslation164.
  ///
  /// In he, this message translates to:
  /// **'שולחנות עבודה'**
  String get literalTranslation164;

  /// No description provided for @literalTranslation165.
  ///
  /// In he, this message translates to:
  /// **'כל שולחנות העבודה'**
  String get literalTranslation165;

  /// No description provided for @literalTranslation166.
  ///
  /// In he, this message translates to:
  /// **'שמור וזכור'**
  String get literalTranslation166;

  /// No description provided for @literalTranslation167.
  ///
  /// In he, this message translates to:
  /// **'ספרים ומעקב לימוד'**
  String get literalTranslation167;

  /// No description provided for @literalTranslation168.
  ///
  /// In he, this message translates to:
  /// **'הגדרות מתקדמות'**
  String get literalTranslation168;

  /// No description provided for @literalTranslation169.
  ///
  /// In he, this message translates to:
  /// **'הגדרות נוספות שדרסת'**
  String get literalTranslation169;

  /// No description provided for @literalTranslation170.
  ///
  /// In he, this message translates to:
  /// **'צור גיבוי עכשיו'**
  String get literalTranslation170;

  /// No description provided for @literalTranslation171.
  ///
  /// In he, this message translates to:
  /// **'שחזר מגיבוי'**
  String get literalTranslation171;

  /// No description provided for @literalTranslation172.
  ///
  /// In he, this message translates to:
  /// **'מצב סייפר'**
  String get literalTranslation172;

  /// No description provided for @literalTranslation173.
  ///
  /// In he, this message translates to:
  /// **'נעילת הגדרות'**
  String get literalTranslation173;

  /// No description provided for @literalTranslation174.
  ///
  /// In he, this message translates to:
  /// **'הפעל מצב סייפר'**
  String get literalTranslation174;

  /// No description provided for @literalTranslation175.
  ///
  /// In he, this message translates to:
  /// **'סיסמה הוגדרה'**
  String get literalTranslation175;

  /// No description provided for @literalTranslation176.
  ///
  /// In he, this message translates to:
  /// **'יש להגדיר סיסמה תחילה'**
  String get literalTranslation176;

  /// No description provided for @literalTranslation177.
  ///
  /// In he, this message translates to:
  /// **'סיסמה'**
  String get literalTranslation177;

  /// No description provided for @literalTranslation178.
  ///
  /// In he, this message translates to:
  /// **'שנה סיסמה'**
  String get literalTranslation178;

  /// No description provided for @literalTranslation179.
  ///
  /// In he, this message translates to:
  /// **'בחר סיסמה'**
  String get literalTranslation179;

  /// No description provided for @literalTranslation180.
  ///
  /// In he, this message translates to:
  /// **'איפוס הגדרות'**
  String get literalTranslation180;

  /// No description provided for @literalTranslation181.
  ///
  /// In he, this message translates to:
  /// **'מחיקת כל ההגדרות וחזרה למצב ההתחלתי'**
  String get literalTranslation181;

  /// No description provided for @literalTranslation182.
  ///
  /// In he, this message translates to:
  /// **'אפס הגדרות'**
  String get literalTranslation182;

  /// No description provided for @literalTranslation183.
  ///
  /// In he, this message translates to:
  /// **'נדרשת הפעלה מחדש'**
  String get literalTranslation183;

  /// No description provided for @literalTranslation184.
  ///
  /// In he, this message translates to:
  /// **'הספרייה נמצאה בהצלחה.\nלחץ על הכפתור להפעלה מחדש של התוכנה.'**
  String get literalTranslation184;

  /// No description provided for @literalTranslation185.
  ///
  /// In he, this message translates to:
  /// **'הספרייה נמצאה בהצלחה.\nלחץ על הכפתור לסגירת האפליקציה, ולאחר מכן פתח אותה מחדש.'**
  String get literalTranslation185;

  /// No description provided for @literalTranslation186.
  ///
  /// In he, this message translates to:
  /// **'הפעל מחדש את התוכנה'**
  String get literalTranslation186;

  /// No description provided for @literalTranslation187.
  ///
  /// In he, this message translates to:
  /// **'סגור את האפליקציה'**
  String get literalTranslation187;

  /// No description provided for @literalTranslation188.
  ///
  /// In he, this message translates to:
  /// **'נדרשת העתקה של קובץ הספרייה'**
  String get literalTranslation188;

  /// No description provided for @literalTranslation189.
  ///
  /// In he, this message translates to:
  /// **'העתק (שמור מקור)'**
  String get literalTranslation189;

  /// No description provided for @literalTranslation190.
  ///
  /// In he, this message translates to:
  /// **'העתק + נסה מחק מקור'**
  String get literalTranslation190;

  /// No description provided for @literalTranslation191.
  ///
  /// In he, this message translates to:
  /// **'העתק'**
  String get literalTranslation191;

  /// No description provided for @literalTranslation192.
  ///
  /// In he, this message translates to:
  /// **'העבר'**
  String get literalTranslation192;

  /// No description provided for @literalTranslation193.
  ///
  /// In he, this message translates to:
  /// **'פתח מקור'**
  String get literalTranslation193;

  /// No description provided for @literalTranslation194.
  ///
  /// In he, this message translates to:
  /// **'אחר כך'**
  String get literalTranslation194;

  /// No description provided for @literalTranslation195.
  ///
  /// In he, this message translates to:
  /// **'סגור עכשיו'**
  String get literalTranslation195;

  /// No description provided for @literalTranslation196.
  ///
  /// In he, this message translates to:
  /// **'כדי להשלים את השינוי יש לסגור ולהפעיל מחדש את התוכנה. האם לסגור עכשיו?'**
  String get literalTranslation196;

  /// No description provided for @literalTranslation197.
  ///
  /// In he, this message translates to:
  /// **'נדרשת בחירה כיצד לשמור את מסד הנתונים'**
  String get literalTranslation197;

  /// No description provided for @literalTranslation198.
  ///
  /// In he, this message translates to:
  /// **'לחץ על כפתור למטה, נווט לאותה תיקייה ובחר את הקובץ seforim.db — האפליקציה תעתיק אותו לאחסון הפנימי.'**
  String get literalTranslation198;

  /// No description provided for @literalTranslation199.
  ///
  /// In he, this message translates to:
  /// **'(אפשרות \"נסה מחק מקור\" — ניסיון למחוק לאחר העתקה. עשויה שלא להצליח בכל גרסאות Android.)'**
  String get literalTranslation199;

  /// No description provided for @literalTranslation200.
  ///
  /// In he, this message translates to:
  /// **'חיפוש...'**
  String get literalTranslation200;

  /// No description provided for @literalTranslation201.
  ///
  /// In he, this message translates to:
  /// **'הגדרות חיפוש'**
  String get literalTranslation201;

  /// No description provided for @literalTranslation202.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו פריטים'**
  String get literalTranslation202;

  /// No description provided for @literalTranslation203.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו תוצאות'**
  String get literalTranslation203;

  /// No description provided for @literalTranslation204.
  ///
  /// In he, this message translates to:
  /// **'חפש בסימניות...'**
  String get literalTranslation204;

  /// No description provided for @literalTranslation205.
  ///
  /// In he, this message translates to:
  /// **'אין סימניות'**
  String get literalTranslation205;

  /// No description provided for @literalTranslation206.
  ///
  /// In he, this message translates to:
  /// **'מחק את כל הסימניות'**
  String get literalTranslation206;

  /// No description provided for @literalTranslation207.
  ///
  /// In he, this message translates to:
  /// **'הסימניה נמחקה'**
  String get literalTranslation207;

  /// No description provided for @literalTranslation208.
  ///
  /// In he, this message translates to:
  /// **'כל הסימניות נמחקו'**
  String get literalTranslation208;

  /// No description provided for @literalTranslation209.
  ///
  /// In he, this message translates to:
  /// **'חפש בהיסטוריה...'**
  String get literalTranslation209;

  /// No description provided for @literalTranslation210.
  ///
  /// In he, this message translates to:
  /// **'אין היסטוריה'**
  String get literalTranslation210;

  /// No description provided for @literalTranslation211.
  ///
  /// In he, this message translates to:
  /// **'מחק את כל ההיסטוריה'**
  String get literalTranslation211;

  /// No description provided for @literalTranslation212.
  ///
  /// In he, this message translates to:
  /// **'נמחק בהצלחה'**
  String get literalTranslation212;

  /// No description provided for @literalTranslation213.
  ///
  /// In he, this message translates to:
  /// **'כל ההיסטוריה נמחקה'**
  String get literalTranslation213;

  /// No description provided for @literalTranslation214.
  ///
  /// In he, this message translates to:
  /// **'חיפוש'**
  String get literalTranslation214;

  /// No description provided for @literalTranslation215.
  ///
  /// In he, this message translates to:
  /// **'מזער'**
  String get literalTranslation215;

  /// No description provided for @literalTranslation216.
  ///
  /// In he, this message translates to:
  /// **'צא ממסך מלא'**
  String get literalTranslation216;

  /// No description provided for @literalTranslation217.
  ///
  /// In he, this message translates to:
  /// **'הטקסט הועתק ללוח'**
  String get literalTranslation217;

  /// No description provided for @literalTranslation218.
  ///
  /// In he, this message translates to:
  /// **'הטקסט המעוצב הועתק ללוח'**
  String get literalTranslation218;

  /// No description provided for @literalTranslation219.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעתקה'**
  String get literalTranslation219;

  /// No description provided for @literalTranslation220.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעתקה מעוצבת'**
  String get literalTranslation220;

  /// No description provided for @literalTranslation221.
  ///
  /// In he, this message translates to:
  /// **'הדף לא נמצא בתוכן העניינים'**
  String get literalTranslation221;

  /// No description provided for @literalTranslation222.
  ///
  /// In he, this message translates to:
  /// **'הספר איננו קיים'**
  String get literalTranslation222;

  /// No description provided for @literalTranslation223.
  ///
  /// In he, this message translates to:
  /// **'ההערה נוצרה והוצבה בסרגל'**
  String get literalTranslation223;

  /// No description provided for @literalTranslation224.
  ///
  /// In he, this message translates to:
  /// **'השינויים נשמרו בהצלחה'**
  String get literalTranslation224;

  /// No description provided for @literalTranslation225.
  ///
  /// In he, this message translates to:
  /// **'הטקסט לא נמצא'**
  String get literalTranslation225;

  /// No description provided for @literalTranslation226.
  ///
  /// In he, this message translates to:
  /// **'אנא בחר טקסט להעתקה'**
  String get literalTranslation226;

  /// No description provided for @literalTranslation227.
  ///
  /// In he, this message translates to:
  /// **'ניקוי טיוטות הושלם'**
  String get literalTranslation227;

  /// No description provided for @literalTranslation228.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get literalTranslation228;

  /// No description provided for @literalTranslation229.
  ///
  /// In he, this message translates to:
  /// **'אישור'**
  String get literalTranslation229;

  /// No description provided for @literalTranslation230.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get literalTranslation230;

  /// No description provided for @literalTranslation231.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get literalTranslation231;

  /// No description provided for @literalTranslation232.
  ///
  /// In he, this message translates to:
  /// **'שמור'**
  String get literalTranslation232;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'he':
      return AppLocalizationsHe();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
