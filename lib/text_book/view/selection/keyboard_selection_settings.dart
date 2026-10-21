import 'package:flutter/painting.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// הגדרות הרינדור שבהן נמדדת בחירה שהגיעה מקיצור מקלדת, כשאין תפריט שמוסר
/// את ההגדרות של התצוגה עצמה.
RenderSettings keyboardSelectionRenderSettings(
  TextBookLoaded state,
  SettingsState settingsState,
) => RenderSettings.fromProfile(
  state.bodyDisplayProfile,
  searchText: state.searchText,
  searchOptions: state.searchOptions,
  alternativeWords: state.alternativeWords,
  spacingValues: state.spacingValues,
  isFuzzySearch: state.searchMode == SearchMode.fuzzy,
  searchMode: state.searchMode,
  searchDistance: state.searchDistance,
  matchPolicy: state.matchPolicy,
  fontSize: state.fontSize,
  fontFamily: settingsState.fontFamily,
  fontWeight: settingsState.fontBold ? FontWeight.bold : null,
  lineHeight: settingsState.lineHeight,
);
