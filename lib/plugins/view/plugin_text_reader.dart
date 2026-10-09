import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';

/// מחליף את תצוגת הטקסט בלבד; זהות הכרטיסייה וההיסטוריה נשמרות.
class PluginTextReader extends StatefulWidget {
  final TextBookTab tab;
  final Widget nativeReader;

  const PluginTextReader({
    super.key,
    required this.tab,
    required this.nativeReader,
  });

  @override
  State<PluginTextReader> createState() => _PluginTextReaderState();
}

class _PluginTextReaderState extends State<PluginTextReader> {
  late int _lastIndex = widget.tab.index;

  @override
  void initState() {
    super.initState();
    PluginTextReaderRegistry.instance.addListener(_syncNavigation);
    _syncNavigation();
  }

  void _syncNavigation() {
    widget.tab.scrollController.externalScroll =
        PluginTextReaderRegistry.instance.usesPlugin(widget.tab)
        ? _navigate
        : null;
  }

  @override
  void didUpdateWidget(covariant PluginTextReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNavigation();
  }

  Future<void> _navigate(int index, {int? sourceLineIndex}) async {
    final state = widget.tab.bloc.state;
    final line =
        sourceLineIndex ??
        (state is TextBookLoaded && state.readingSegments.isNotEmpty
            ? state
                  .readingSegments[index.clamp(
                    0,
                    state.readingSegments.length - 1,
                  )]
                  .startLineIndex
            : index);
    widget.tab.index = line;
    _lastIndex = line;
    widget.tab.bloc.add(UpdateVisibleIndecies([line]));
    final registry = PluginTextReaderRegistry.instance;
    final plugin = registry.activePlugin;
    if (plugin == null || !registry.usesPlugin(widget.tab)) return;
    await PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
      plugin.pluginId,
      'reader.textReaderNavigate',
      PluginTextReaderRegistry.bookPayload(widget.tab),
      instanceId: registry.instanceIdFor(widget.tab),
      resumeForegroundIfNeeded: true,
    );
  }

  @override
  void dispose() {
    PluginTextReaderRegistry.instance.removeListener(_syncNavigation);
    widget.tab.scrollController.externalScroll = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = PluginTextReaderRegistry.instance;
    return BlocListener<TabsBloc, TabsState>(
      listener: (context, state) {
        final plugin = registry.activePlugin;
        if (plugin == null || !registry.usesPlugin(widget.tab)) return;
        if (_lastIndex == widget.tab.index) return;
        _lastIndex = widget.tab.index;
        PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
          plugin.pluginId,
          'reader.textReaderNavigate',
          PluginTextReaderRegistry.bookPayload(widget.tab),
          instanceId: registry.instanceIdFor(widget.tab),
          resumeForegroundIfNeeded: true,
        );
      },
      child: BlocListener<TextBookBloc, TextBookState>(
        listenWhen: (previous, current) =>
            current is TextBookLoaded &&
            (previous is! TextBookLoaded ||
                previous.fontSize != current.fontSize ||
                previous.bodyDisplayProfile != current.bodyDisplayProfile),
        listener: (context, state) {
          // ההגבלה ידועה רק במצב Loaded; היא מחזירה את הטאב לקורא הרגיל.
          if (state is TextBookLoaded && state.protection.isProtected) {
            setState(() {});
            return;
          }
          registry.command(widget.tab, 'display');
        },
        child: ListenableBuilder(
          listenable: registry,
          builder: (context, child) {
            final plugin = registry.activePlugin;
            if (plugin == null || !registry.usesPlugin(widget.tab)) {
              return widget.nativeReader;
            }
            return PluginTabPage(
              key: ValueKey(
                '${plugin.pluginId}-${plugin.version}-${plugin.updatedAt}',
              ),
              plugin: plugin,
              instanceId: registry.instanceIdFor(widget.tab),
              readerTab: widget.tab,
            );
          },
        ),
      ),
    );
  }
}
