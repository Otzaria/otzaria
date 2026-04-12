import 'package:flutter/material.dart';
import 'package:otzaria/l10n/app_localizations.dart';

export 'package:otzaria/l10n/app_localizations.dart';

extension AppLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  bool get isEnglishMode => l10n.localeName == 'en';

  String t(String key) {
    return switch (key) {
      'app.title' => l10n.appTitle,
      'settings.title' => l10n.settingsTitle,
      'settings.back' => l10n.settingsBack,
      'settings.tab.design' => l10n.settingsTabDesign,
      'settings.tab.text' => l10n.settingsTabText,
      'settings.tab.library' => l10n.settingsTabLibrary,
      'settings.tab.tools' => l10n.settingsTabTools,
      'settings.tab.shortcuts' => l10n.settingsTabShortcuts,
      'settings.tab.system' => l10n.settingsTabSystem,
      'settings.tab.about' => l10n.settingsTabAbout,
      'settings.group.displayContent' => l10n.settingsGroupDisplayContent,
      'settings.group.tools' => l10n.settingsGroupTools,
      'settings.group.system' => l10n.settingsGroupSystem,
      'settings.language.cardTitle' => l10n.settingsLanguageCardTitle,
      'settings.language.title' => l10n.settingsLanguageTitle,
      'settings.language.subtitle.he' => l10n.settingsLanguageSubtitleHe,
      'settings.language.subtitle.en' => l10n.settingsLanguageSubtitleEn,
      'settings.language.hebrew' => l10n.settingsLanguageHebrew,
      'settings.language.english' => l10n.settingsLanguageEnglish,
      'settings.language.restartHint' => l10n.settingsLanguageRestartHint,
      _ => key,
    };
  }
}
