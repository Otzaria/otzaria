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
