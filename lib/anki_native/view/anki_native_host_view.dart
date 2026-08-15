import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/anki_native/bloc/anki_native_bloc.dart';
import 'package:otzaria/anki_native/bloc/anki_native_event.dart';
import 'package:otzaria/anki_native/bloc/anki_native_state.dart';
import 'package:otzaria/anki_native/models/anki_native_window.dart';
import 'package:otzaria/anki_native/repository/anki_native_repository.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

class AnkiNativeHostView extends StatefulWidget {
  final VoidCallback onFallback;

  const AnkiNativeHostView({super.key, required this.onFallback});

  @override
  State<AnkiNativeHostView> createState() => _AnkiNativeHostViewState();
}

class _AnkiNativeHostViewState extends State<AnkiNativeHostView> {
  late final AnkiNativeBloc _bloc = AnkiNativeBloc(
    repository: LocalAnkiNativeRepository(),
  )..add(const StartAnkiNative());
  ValueListenable<TickerModeData>? _tickerMode;
  bool? _lastVisible;
  bool _fallbackScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_reportVisibility);
      _tickerMode = notifier;
      notifier.addListener(_reportVisibility);
    }
    _reportVisibility();
  }

  void _reportVisibility() {
    final visible = _tickerMode?.value.enabled ?? true;
    if (_lastVisible == visible) return;
    _lastVisible = visible;
    _bloc.add(SetAnkiNativeVisibility(visible));
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_reportVisibility);
    unawaited(_bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<AnkiNativeBloc, AnkiNativeState>(
        listener: (context, state) {
          if (state is! AnkiNativeFailure ||
              !state.canUseFallback ||
              _fallbackScheduled) {
            return;
          }
          _fallbackScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onFallback();
          });
        },
        builder: (context, state) => switch (state) {
          AnkiNativeInitial() || AnkiNativeLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
          AnkiNativeFailure(:final message) => _FailureView(
            message: message,
            onRetry: () => _bloc.add(const StartAnkiNative()),
          ),
          final AnkiNativeReady ready => _ReadyView(state: ready),
        },
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  final AnkiNativeReady state;
  const _ReadyView({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _WindowToolbar(state: state),
        Expanded(
          child: _NativeViewport(
            onBounds: (bounds) => context.read<AnkiNativeBloc>().add(
              UpdateAnkiNativeBounds(bounds),
            ),
          ),
        ),
      ],
    );
  }
}

class _WindowToolbar extends StatelessWidget {
  final AnkiNativeReady state;
  const _WindowToolbar({required this.state});

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedWindow;
    return ColoredBox(
      color: AppSurfaces.panelBackground(context),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMD),
          child: Row(
            children: [
              const Text('חלונות Anki:'),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.windows.length,
                  separatorBuilder: (_, _) => const SizedBox(
                    width: AppTokens.spaceSM,
                  ),
                  itemBuilder: (context, index) {
                    final window = state.windows[index];
                    final selected = window.targetId == state.selectedTargetId;
                    void onPressed() => context.read<AnkiNativeBloc>().add(
                      SelectAnkiWindow(window.targetId),
                    );
                    return selected
                        ? ActionButton.recommended(
                            text: _windowTitle(window),
                            onPressed: onPressed,
                          )
                        : ActionButton.neutral(
                            text: _windowTitle(window),
                            onPressed: onPressed,
                          );
                  },
                ),
              ),
              if (selected?.closable == true) ...[
                const SizedBox(width: AppTokens.spaceSM),
                ActionButton.neutral(
                  text: 'סגור חלון',
                  onPressed: () => context.read<AnkiNativeBloc>().add(
                    const CloseSelectedAnkiWindow(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _windowTitle(AnkiNativeWindow window) =>
      window.title.trim().isEmpty ? 'Anki' : window.title.trim();
}

class _NativeViewport extends StatefulWidget {
  final ValueChanged<AnkiNativeBounds> onBounds;
  const _NativeViewport({required this.onBounds});

  @override
  State<_NativeViewport> createState() => _NativeViewportState();
}

class _NativeViewportState extends State<_NativeViewport>
    with WidgetsBindingObserver {
  final GlobalKey _viewportKey = GlobalKey();
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => _scheduleSync();

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final renderObject = _viewportKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final offset = renderObject.localToGlobal(Offset.zero);
      final ratio = View.of(context).devicePixelRatio;
      final width = (renderObject.size.width * ratio).round();
      final height = (renderObject.size.height * ratio).round();
      if (width <= 0 || height <= 0) return;
      widget.onBounds(
        AnkiNativeBounds(
          x: (offset.dx * ratio).round(),
          y: (offset.dy * ratio).round(),
          width: width,
          height: height,
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSync();
    return ColoredBox(
      key: _viewportKey,
      color: Theme.of(context).colorScheme.surface,
    );
  }
}

class _FailureView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _FailureView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.plug_disconnected_24_regular,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              'לא ניתן לחבר את חלון Anki',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppTokens.spaceLG),
            ActionButton.recommended(text: 'נסה שוב', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
