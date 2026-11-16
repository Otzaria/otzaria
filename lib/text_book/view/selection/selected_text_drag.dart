import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:super_native_extensions/raw_clipboard.dart';
import 'package:super_native_extensions/raw_drag_drop.dart';

typedef SelectedTextDragContent = ({
  String plainText,
  String htmlText,
  String fontFamily,
  double fontSize,
});

/// Windows CF_HTML: offsets are UTF-8 *byte* positions, not Dart code units.
Uint8List buildWindowsHtmlDragData(String html) {
  const prefix = '<html><body><!--StartFragment-->';
  const suffix = '<!--EndFragment--></body></html>';
  String offset(int value) => value.toString().padLeft(10, '0');
  String header(int startHtml, int endHtml, int startFragment, int endFragment) =>
      'Version:0.9\r\n'
      'StartHTML:${offset(startHtml)}\r\n'
      'EndHTML:${offset(endHtml)}\r\n'
      'StartFragment:${offset(startFragment)}\r\n'
      'EndFragment:${offset(endFragment)}\r\n';

  final startHtml = utf8.encode(header(0, 0, 0, 0)).length;
  final startFragment = startHtml + utf8.encode(prefix).length;
  final endFragment = startFragment + utf8.encode(html).length;
  final endHtml = endFragment + utf8.encode(suffix).length;
  return Uint8List.fromList(
    utf8.encode(
      '${header(startHtml, endHtml, startFragment, endFragment)}$prefix$html$suffix',
    ),
  );
}

/// A native Windows drag is allowed only when it began inside an existing
/// selection, with the primary mouse button held past the motion threshold.
@visibleForTesting
bool shouldStartSelectedTextDrag({
  required bool isSelectedTextHit,
  required bool primaryMouseHeld,
  required double distance,
}) =>
    isSelectedTextHit && primaryMouseHeld && distance >= kTouchSlop;

/// Adds Windows-to-Word drag without participating in Flutter's gesture arena.
/// A normal first drag still creates/extends a selection; only a second drag
/// beginning on already selected text starts the native OS drag.
class SelectedTextDragRegion extends StatefulWidget {
  const SelectedTextDragRegion({
    super.key,
    required this.selectedText,
    required this.prepareContent,
    required this.child,
  });

  final String? Function() selectedText;
  final Future<SelectedTextDragContent?> Function(String capturedText)
      prepareContent;
  final Widget child;

  @override
  State<SelectedTextDragRegion> createState() => _SelectedTextDragRegionState();
}

class _SelectedTextDragRegionState extends State<SelectedTextDragRegion> {
  int? _pointer;
  Offset? _start;
  String? _selectionAtDown;
  bool _dragging = false;

  void _down(PointerDownEvent event) {
    _pointer = null;
    _start = null;
    _selectionAtDown = null;
    if (_dragging ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final selected = widget.selectedText();
    if (selected == null || selected.trim().isEmpty) return;
    final root = context.findRenderObject();
    if (root == null ||
        clickIsOnSelectionWithinArea(
              root: root,
              globalPosition: event.position,
              selectedText: selected,
            ) !=
            true) {
      return;
    }
    _pointer = event.pointer;
    _start = event.position;
    _selectionAtDown = selected;
  }

  void _move(PointerMoveEvent event) {
    final start = _start;
    final selected = _selectionAtDown;
    if (_dragging || _pointer != event.pointer || start == null || selected == null) {
      return;
    }
    if (!shouldStartSelectedTextDrag(
      isSelectedTextHit: true,
      primaryMouseHeld: event.buttons & kPrimaryMouseButton != 0,
      distance: (event.position - start).distance,
    )) {
      return;
    }
    _pointer = null;
    _start = null;
    _selectionAtDown = null;
    _dragging = true;
    // Begin building the content before cancelling the Flutter selection
    // recognizers, which might otherwise clear the selected paragraph index.
    final prepared = widget.prepareContent(selected);
    GestureBinding.instance.cancelPointer(event.pointer);
    unawaited(_startSystemDrag(
      prepared,
      position: event.position,
      pointer: event.pointer,
      fallbackText: selected,
    ));
  }

  void _up(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _start = null;
    _selectionAtDown = null;
  }

  Future<void> _startSystemDrag(
    Future<SelectedTextDragContent?> prepared, {
    required Offset position,
    required int pointer,
    required String fallbackText,
  }) async {
    DataProviderHandle? handle;
    DragConfiguration? configuration;
    bool started = false;
    try {
      final content = await prepared;
      if (!mounted || content == null || content.plainText.trim().isEmpty) return;
      final plain = withoutDivineNameJoiners(content.plainText).trimRight();
      final html = CopyUtils.buildStyledHtml(
        htmlText: withoutDivineNameJoiners(content.htmlText),
        fontFamily: content.fontFamily,
        fontSize: content.fontSize,
      );
      handle = await DataProvider(representations: [
        // Windows CF_UNICODETEXT (13), rather than a custom "text/plain" format.
        DataRepresentation.simple(format: 'NativeShell_CF_13', data: plain),
        DataRepresentation.simple(
          format: 'HTML Format',
          data: buildWindowsHtmlDragData(html),
        ),
      ]).register();
      if (!mounted) return;
      final dragContext = await DragContext.instance();
      if (!mounted) return;
      final snapshot = await _preview(fallbackText);
      if (!mounted) {
        snapshot.dispose();
        return;
      }
      configuration = DragConfiguration(
        items: [
          DragItem(
            dataProvider: handle,
            image: TargetedWidgetSnapshot(
              WidgetSnapshot.image(snapshot),
              Rect.fromLTWH(position.dx - 12, position.dy - 20, 240, 44),
            ),
            liftImage: null,
          ),
        ],
        allowedOperations: [DropOperation.copy],
      );
      final session = dragContext.newSession(pointer: pointer);
      session.dragCompleted.addListener(() {
        _dragging = false;
      });
      await dragContext.startDrag(
        buildContext: context,
        session: session,
        configuration: configuration,
        position: position,
      );
      started = true;
    } catch (error) {
      debugPrint('Selected text drag failed: $error');
    } finally {
      configuration?.disposeImages();
      if (!started && handle != null) await handle.dispose();
      if (!started || !mounted) _dragging = false;
    }
  }

  Future<ui.Image> _preview(String text) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, 240, 44);
    final colors = Theme.of(context).colorScheme;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(AppTokens.radius)),
      Paint()..color = colors.surface,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text.replaceAll('\n', ' '),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.rtl,
    );
    painter.layout(maxWidth: 216);
    painter.paint(canvas, const Offset(12, 10));
    painter.dispose();
    return recorder.endRecording().toImage(240, 44);
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.windows) {
      return widget.child;
    }
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}
