class SettingsState {
  const SettingsState(this.compactMenuMode);

  final bool compactMenuMode;
}

// ui-lint: allow UIL-025 — המעבר להגדרות של הצפיפות עצמה, שמציג את הערך השמור
bool saved(SettingsState state) => state.compactMenuMode;
