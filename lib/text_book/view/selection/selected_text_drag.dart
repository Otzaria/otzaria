import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

typedef SelectedTextDragPreparation =
    Future<SelectedTextDragContent?> Function();

/// Windows CF_HTML: offsets are UTF-8 *byte* positions, not Dart code units.
Uint8List buildWindowsHtmlDragData(String html) {
  const prefix = '<html><body><!--StartFragment-->';
  const suffix = '<!--EndFragment--></body></html>';
  String offset(int value) => value.toString().padLeft(10, '0');
  String header(
    int startHtml,
    int endHtml,
    int startFragment,
    int endFragment,
  ) =>
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
}) => isSelectedTextHit && primaryMouseHeld && distance >= kTouchSlop;

/// Adds Windows-to-Word drag without participating in Flutter's gesture arena.
/// A normal first drag still creates/extends a selection; only a second drag
/// beginning on already selected text starts the native OS drag.
class SelectedTextDragRegion extends StatefulWidget {
  const SelectedTextDragRegion({
    super.key,
    required this.selectedText,
    required this.captureContent,
    required this.child,
  });

  final String? Function() selectedText;

  /// Captures source indices, protection and formatting before selection changes.
  /// The returned preparation runs only after the drag threshold is crossed.
  final SelectedTextDragPreparation? Function(String capturedText)
  captureContent;
  final Widget child;

  @override
  State<SelectedTextDragRegion> createState() => _SelectedTextDragRegionState();
}

class _SelectedTextDragRegionState extends State<SelectedTextDragRegion> {
  int? _pointer;
  Offset? _start;
  String? _selectionAtDown;
  SelectedTextDragPreparation? _prepareAtDown;
  bool _dragging = false;
  DragContext? _pendingContext;
  DragSession? _pendingSession;

  void _cancelPendingSession() {
    final session = _pendingSession;
    if (session?.dragStarted == true) return;
    _pendingSession = null;
    if (session != null) _pendingContext?.cancelSession(session);
    _pendingContext = null;
  }

  @override
  void dispose() {
    _cancelPendingSession();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    _cancelPendingSession();
    _pointer = null;
    _start = null;
    _selectionAtDown = null;
    _prepareAtDown = null;
    if (_dragging ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final selected = widget.selectedText();
    if (selected == null || selected.trim().isEmpty) return;
    if (!_isOnSelection(event.position)) return;
    final prepare = widget.captureContent(selected);
    if (prepare == null) return;
    _prepareAtDown = prepare;
    _pointer = event.pointer;
    _start = event.position;
    _selectionAtDown = selected;
  }

  bool _isOnSelection(Offset position) {
    var hit = false;
    void visit(Element element) {
      if (hit) return;
      final container = element.widget;
      if (container is SelectionContainer) {
        final root = element.findRenderObject();
        if (root is RenderBox) {
          final local = root.globalToLocal(position);
          hit =
              container.delegate?.value.selectionRects.any(
                (rect) => rect.contains(local),
              ) ??
              false;
        }
        // The outer delegate already aggregates its nested selection containers.
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return hit;
  }

  void _move(PointerMoveEvent event) {
    final start = _start;
    final selected = _selectionAtDown;
    final prepare = _prepareAtDown;
    if (_dragging ||
        _pointer != event.pointer ||
        start == null ||
        selected == null ||
        prepare == null) {
      return;
    }
    if (!shouldStartSelectedTextDrag(
      isSelectedTextHit: true,
      primaryMouseHeld: event.buttons & kPrimaryMouseButton != 0,
      distance: (event.position - start).distance,
    )) {
      return;
    }
    _start = null;
    _selectionAtDown = null;
    _prepareAtDown = null;
    _dragging = true;
    final prepared = prepare();
    unawaited(
      _startSystemDrag(
        prepared,
        position: event.position,
        pointer: event.pointer,
        fallbackText: selected,
      ),
    );
  }

  void _up(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _cancelPendingSession();
    _pointer = null;
    _start = null;
    _selectionAtDown = null;
    _prepareAtDown = null;
  }

  Future<void> _startSystemDrag(
    Future<SelectedTextDragContent?> prepared, {
    required Offset position,
    required int pointer,
    required String fallbackText,
  }) async {
    bool isActive() => mounted && _pointer == pointer;

    DataProviderHandle? handle;
    DragConfiguration? configuration;
    bool started = false;
    try {
      final content = await prepared;
      if (!isActive() || content == null || content.plainText.trim().isEmpty) {
        return;
      }
      final plain = withoutDivineNameJoiners(content.plainText).trimRight();
      final html = CopyUtils.buildStyledHtml(
        htmlText: withoutDivineNameJoiners(content.htmlText),
        fontFamily: content.fontFamily,
        fontSize: content.fontSize,
      );
      handle = await DataProvider(
        representations: [
          // Windows CF_UNICODETEXT (13), rather than a custom "text/plain" format.
          DataRepresentation.simple(format: 'NativeShell_CF_13', data: plain),
          DataRepresentation.simple(
            format: 'HTML Format',
            data: buildWindowsHtmlDragData(html),
          ),
        ],
      ).register();
      if (!isActive()) return;
      final dragContext = await DragContext.instance();
      if (!isActive()) return;
      final snapshot = await _preview(fallbackText);
      if (!isActive()) {
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
      _pendingContext = dragContext;
      _pendingSession = session;
      session.dragCompleted.addListener(() {
        if (session.dragStarted) _dragging = false;
      });
      if (!mounted) return;
      await dragContext.startDrag(
        buildContext: context,
        session: session,
        configuration: configuration,
        position: position,
      );
      started = session.dragStarted;
      _pendingContext = null;
      _pendingSession = null;
      // Keep receiving release/cancel while preparing and serializing the request.
      GestureBinding.instance.cancelPointer(pointer);
    } catch (error) {
      debugPrint('Selected text drag failed: $error');
    } finally {
      _cancelPendingSession();
      if (_pointer == pointer) _pointer = null;
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
      RRect.fromRectAndRadius(
        rect.deflate(1),
        const Radius.circular(AppTokens.radius),
      ),
      Paint()..color = colors.surface,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text.replaceAll('\n', ' '),
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.onSurface),
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
    if (kIsWeb || Theme.of(context).platform != TargetPlatform.windows) {
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
