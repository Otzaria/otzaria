import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/messages_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/reports/view_scope.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// מציג תמונה מצורפת בגדול. כש-[accept] מועבר אפשר לסמן עליה אזורים; מחזיר
/// את התמונה המסומנת (PNG), או null כשלא נשמר סימון.
Future<AppReportImage?> showAppReportImageViewer(
  BuildContext context,
  AppReportImage image, {
  AppReportMarkedImageCheck? accept,
}) => showDialogUntilTornDown<AppReportImage>(
  context: context,
  builder: reportDialogBuilder(
    context,
    (_) => AppReportImageViewer(image: image, accept: accept),
  ),
);

/// false כשהתמונה המסומנת חורגת מהמכסות; הבודק מציג את ההודעה, והצופה נשאר
/// פתוח כדי שהסימון לא יאבד.
typedef AppReportMarkedImageCheck = bool Function(AppReportImage marked);

class AppReportImageViewer extends StatefulWidget {
  const AppReportImageViewer({
    super.key,
    required this.image,
    this.accept,
  });

  final AppReportImage image;
  final AppReportMarkedImageCheck? accept;

  bool get editable => accept != null;

  @override
  State<AppReportImageViewer> createState() => _AppReportImageViewerState();
}

class _AppReportImageViewerState extends State<AppReportImageViewer> {
  final _transform = TransformationController();
  final _dirty = ValueNotifier(false);
  final _marks = <Rect>[];
  ui.Image? _decoded;
  bool _failed = false;
  bool _marking = false;
  bool _saving = false;
  Offset? _dragStart;
  int? _dragPointer;
  Rect? _draft;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _decoded?.dispose();
    _transform.dispose();
    _dirty.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.image.bytes);
      final ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _decoded = frame.image);
    } catch (error, stackTrace) {
      debugPrint('App report image decode failed: $error\n$stackTrace');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _setMarks(void Function() change) {
    setState(change);
    _dirty.value = _marks.isNotEmpty;
  }

  void _endDrag() {
    final draft = _draft;
    final image = _decoded;
    _dragStart = null;
    _dragPointer = null;
    _draft = null;
    if (draft == null || image == null) return setState(() {});
    final minSide = _strokeWidth(image) * 2;
    _setMarks(() {
      if (draft.width >= minSide && draft.height >= minSide) _marks.add(draft);
    });
  }

  Future<void> _save() async {
    final image = _decoded;
    if (image == null || _marks.isEmpty) return;
    setState(() => _saving = true);
    try {
      final marked = await _renderMarked(image);
      if (!mounted) return;
      if (widget.accept!(marked)) {
        Navigator.of(context).pop(marked);
      } else {
        setState(() => _saving = false);
      }
    } catch (error, stackTrace) {
      debugPrint('App report image marking failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      UiSnack.showError(
        context.settingsText(ReportMessages.appReportImageMarkFailed),
      );
    }
  }

  Future<AppReportImage> _renderMarked(ui.Image image) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
    _paintMarks(canvas, _marks, image);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(image.width, image.height);
    picture.dispose();
    try {
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG encoding returned no data');
      return AppReportImage(
        bytes: data.buffer.asUint8List(),
        fileName: _pngFileName(widget.image.fileName),
        mimeType: 'image/png',
      );
    } finally {
      rendered.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoded = _decoded;
    final canMark = widget.editable && decoded != null && !_saving;
    return AppDialogFrame(
      title: context.settingsText('צפייה בתמונה'),
      subtitle: widget.image.fileName,
      subtitleMaxLines: 1,
      icon: FluentIcons.image_24_regular,
      size: AppDialogSize.full,
      isDirty: widget.editable ? _dirty : null,
      confirmDiscard: confirmDiscardChanges,
      closeEnabled: !_saving,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.editable) ...[
            AppIconButton(
              key: const ValueKey('app-report-image-mark'),
              icon: const Icon(FluentIcons.draw_shape_24_regular),
              tooltip: context.settingsText('סימון אזור בתמונה'),
              size: AppIconButtonSize.medium,
              isSelected: _marking,
              onPressed: canMark
                  ? () => setState(() {
                      _marking = !_marking;
                      _dragStart = null;
                      _dragPointer = null;
                      _draft = null;
                    })
                  : null,
            ),
            AppIconButton(
              key: const ValueKey('app-report-image-undo'),
              icon: const Icon(FluentIcons.arrow_undo_24_regular),
              tooltip: context.settingsText('ביטול הסימון האחרון'),
              size: AppIconButtonSize.medium,
              onPressed: canMark && _marks.isNotEmpty
                  ? () => _setMarks(_marks.removeLast)
                  : null,
            ),
          ],
          AppIconButton(
            icon: const Icon(FluentIcons.zoom_fit_24_regular),
            tooltip: context.settingsText('התאמה לחלון'),
            size: AppIconButtonSize.medium,
            onPressed: () => _transform.value = Matrix4.identity(),
          ),
        ],
      ),
      actions: [
        ActionButton.neutral(
          text: context.settingsText('סגור'),
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        ),
        if (widget.editable)
          ActionButton.recommended(
            key: const ValueKey('app-report-image-save-marks'),
            text: context.settingsText('שמירת הסימון'),
            isLoading: _saving,
            onPressed: canMark && _marks.isNotEmpty ? _save : null,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.settingsText(
              _marking
                  ? 'גררו על התמונה כדי לסמן אזור.'
                  : 'גלגלת העכבר או צביטה מגדילות את התמונה.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Expanded(child: ClipRect(child: _body(theme.colorScheme, decoded))),
        ],
      ),
    );
  }

  Widget _body(ColorScheme colorScheme, ui.Image? decoded) {
    if (_failed) {
      return Center(
        child: Icon(
          FluentIcons.image_off_24_regular,
          size: AppTokens.iconXL,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (decoded == null) {
      return const LoadingIndicator();
    }
    return InteractiveViewer(
      transformationController: _transform,
      maxScale: 10,
      panEnabled: !_marking,
      scaleEnabled: !_marking,
      child: Center(
        child: AspectRatio(
          aspectRatio: decoded.width / decoded.height,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _canvas(decoded, decoded.width / constraints.maxWidth),
          ),
        ),
      ),
    );
  }

  /// [toImage] ממיר מקואורדינטות התצוגה לפיקסלים של התמונה המקורית.
  Widget _canvas(ui.Image image, double toImage) {
    Offset imagePoint(Offset local) => Offset(
      (local.dx * toImage).clamp(0, image.width.toDouble()),
      (local.dy * toImage).clamp(0, image.height.toDouble()),
    );
    return Listener(
      onPointerDown: _marking
          ? (event) {
              if (_dragPointer != null) return;
              if (event.buttons & kPrimaryButton == 0) return;
              _dragPointer = event.pointer;
              _dragStart = imagePoint(event.localPosition);
            }
          : null,
      onPointerMove: _marking
          ? (event) {
              final start = _dragStart;
              if (start == null || event.pointer != _dragPointer) return;
              setState(
                () => _draft = Rect.fromPoints(
                  start,
                  imagePoint(event.localPosition),
                ),
              );
            }
          : null,
      onPointerUp: _marking
          ? (event) {
              if (event.pointer == _dragPointer) _endDrag();
            }
          : null,
      onPointerCancel: _marking
          ? (event) {
              if (event.pointer != _dragPointer) return;
              setState(() {
                _dragStart = null;
                _dragPointer = null;
                _draft = null;
              });
            }
          : null,
      child: MouseRegion(
        cursor: _marking ? SystemMouseCursors.precise : MouseCursor.defer,
        child: CustomPaint(
          key: const ValueKey('app-report-image-canvas'),
          foregroundPainter: _MarksPainter(
            marks: [..._marks, ?_draft],
            image: image,
          ),
          child: RawImage(image: image, fit: BoxFit.fill),
        ),
      ),
    );
  }
}

// ui-lint: allow UIL-015 — הסימון נצרב בתמונה המצורפת, ולכן צבעו קבוע בכל ערכת נושא (תוכן, DD-24)
const _markColor = Color(0xFFE53935);

double _strokeWidth(ui.Image image) =>
    math.max(3, math.min(image.width, image.height) / 150);

/// מצייר את הסימונים בקואורדינטות של התמונה המקורית.
void _paintMarks(Canvas canvas, List<Rect> marks, ui.Image image) {
  final paint = Paint()
    ..color = _markColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = _strokeWidth(image);
  for (final mark in marks) {
    canvas.drawRect(mark, paint);
  }
}

String _pngFileName(String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  return '${base.isEmpty ? 'image' : base}.png';
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({required this.marks, required this.image});

  final List<Rect> marks;
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    if (marks.isEmpty) return;
    canvas
      ..save()
      ..scale(size.width / image.width);
    _paintMarks(canvas, marks, image);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarksPainter oldDelegate) =>
      oldDelegate.image != image || !listEquals(oldDelegate.marks, marks);
}
