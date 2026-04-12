// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Otzaria';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsBack => 'Back (Backspace)';

  @override
  String get settingsTabDesign => 'Appearance';

  @override
  String get settingsTabText => 'Text';

  @override
  String get settingsTabLibrary => 'Library';

  @override
  String get settingsTabTools => 'Tools';

  @override
  String get settingsTabShortcuts => 'Shortcuts';

  @override
  String get settingsTabSystem => 'System';

  @override
  String get settingsTabAbout => 'About';

  @override
  String get settingsGroupDisplayContent => 'Display and Content';

  @override
  String get settingsGroupTools => 'Tools';

  @override
  String get settingsGroupSystem => 'System';

  @override
  String get settingsLanguageCardTitle => 'Language';

  @override
  String get settingsLanguageTitle => 'Interface Language';

  @override
  String get settingsLanguageSubtitleHe => 'The interface is shown in Hebrew';

  @override
  String get settingsLanguageSubtitleEn => 'The interface is shown in English';

  @override
  String get settingsLanguageHebrew => 'עברית';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRestartHint =>
      'Some screens update immediately. Text that has not been moved to localization yet will stay in Hebrew.';
}
