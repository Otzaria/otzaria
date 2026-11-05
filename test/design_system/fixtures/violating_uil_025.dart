class SettingsState {
  const SettingsState(this.compactMenuMode);

  final bool compactMenuMode;
}

class SettingsBloc {
  SettingsState state = const SettingsState(false);
}

bool a(SettingsState state) => state.compactMenuMode; // LINT
bool b(SettingsBloc bloc) => bloc.state.compactMenuMode; // LINT
double c(SettingsState s) => s.compactMenuMode ? 36 : 44; // LINT
