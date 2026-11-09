import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/update_check_frequency.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import '../bloc/android_update_bloc.dart';
import '../bloc/android_update_event.dart';
import '../repository/android_update_repository.dart';

class AndroidUpdateScope extends InheritedWidget {
  const AndroidUpdateScope({
    super.key,
    required this.bloc,
    required super.child,
  });
  final AndroidUpdateBloc bloc;

  static AndroidUpdateBloc? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AndroidUpdateScope>()?.bloc;

  @override
  bool updateShouldNotify(AndroidUpdateScope oldWidget) =>
      bloc != oldWidget.bloc;
}

class AndroidUpdateHost extends StatefulWidget {
  const AndroidUpdateHost({super.key, required this.child});
  final Widget child;

  @override
  State<AndroidUpdateHost> createState() => _AndroidUpdateHostState();
}

class _AndroidUpdateHostState extends State<AndroidUpdateHost>
    with WidgetsBindingObserver {
  late final AndroidUpdateBloc _bloc;
  StreamSubscription<SettingsState>? _settings;
  StreamSubscription<TourState>? _tour;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsBloc>();
    final tour = context.read<TourCubit>();
    _bloc = AndroidUpdateBloc(
      repository: DefaultAndroidUpdateRepository(),
      networkAllowed: () => settings.state.canUseSoftwareAndBookUpdates,
      checkDue: () =>
          !kDebugMode &&
          !tour.state.isActive &&
          isAutoUpdateCheckDue(SettingsRepository.keyLastSoftwareUpdateCheck),
      recordSuccessfulCheck: () => recordSuccessfulUpdateCheck(
        SettingsRepository.keyLastSoftwareUpdateCheck,
      ),
    );
    var allowed = settings.state.canUseSoftwareAndBookUpdates;
    _settings = settings.stream.listen((state) {
      final next = state.canUseSoftwareAndBookUpdates;
      if (_started && next && !allowed) {
        _bloc.add(const AndroidUpdateCheck(automatic: true));
      }
      if (_started && !next && allowed) _bloc.add(const AndroidUpdateCancel());
      allowed = next;
    });
    var touring = tour.state.isActive;
    _tour = tour.stream.listen((state) {
      if (_started && touring && !state.isActive) {
        _bloc.add(const AndroidUpdateCheck(automatic: true));
      }
      touring = state.isActive;
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _started = true;
      _bloc.add(const AndroidUpdateInitialize());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_started && state == AppLifecycleState.resumed) {
      _bloc.add(const AndroidUpdateResumed());
    }
  }

  @override
  Widget build(BuildContext context) =>
      AndroidUpdateScope(bloc: _bloc, child: widget.child);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_settings?.cancel());
    unawaited(_tour?.cancel());
    unawaited(_bloc.close());
    super.dispose();
  }
}
