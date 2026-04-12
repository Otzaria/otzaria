// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get appTitle => 'אוצריא';

  @override
  String get settingsTitle => 'הגדרות';

  @override
  String get settingsBack => 'חזור (Backspace)';

  @override
  String get settingsTabDesign => 'מראה';

  @override
  String get settingsTabText => 'כתב';

  @override
  String get settingsTabLibrary => 'ספריה';

  @override
  String get settingsTabTools => 'כלים';

  @override
  String get settingsTabShortcuts => 'קיצורים';

  @override
  String get settingsTabSystem => 'מערכת';

  @override
  String get settingsTabAbout => 'אודות';

  @override
  String get settingsGroupDisplayContent => 'תצוגה ותוכן';

  @override
  String get settingsGroupTools => 'כלים';

  @override
  String get settingsGroupSystem => 'מערכת';

  @override
  String get settingsLanguageCardTitle => 'שפה';

  @override
  String get settingsLanguageTitle => 'שפת ממשק';

  @override
  String get settingsLanguageSubtitleHe => 'הממשק מוצג בעברית';

  @override
  String get settingsLanguageSubtitleEn => 'הממשק מוצג באנגלית';

  @override
  String get settingsLanguageHebrew => 'עברית';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRestartHint =>
      'חלק מהמסכים יתעדכנו מיד, וטקסטים שעדיין לא הועברו לקובץ התרגום יישארו בעברית.';
}
