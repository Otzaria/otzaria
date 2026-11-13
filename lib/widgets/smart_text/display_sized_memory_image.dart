import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// מידות התמונה בפיקסלים מכותרת PNG או JPEG, בלי לפענח אותה.
///
/// מחזיר null לפורמט אחר, ול-JPEG עם Exif — הסיבוב שבו עשוי להחליף רוחב וגובה.
({int width, int height})? encodedImagePixelSize(Uint8List bytes) {
  int u16(int i) => (bytes[i] << 8) | bytes[i + 1];
  int u32(int i) => (u16(i) << 16) | u16(i + 2);

  const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length >= 24) {
    var isPng = true;
    for (var i = 0; i < pngSignature.length; i++) {
      if (bytes[i] != pngSignature[i]) isPng = false;
    }
    if (isPng) return _positive(u32(16), u32(20));
  }

  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) return null;
    final marker = bytes[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    final segmentLength = u16(i + 2);
    final isExif =
        marker == 0xE1 &&
        bytes[i + 4] == 0x45 &&
        bytes[i + 5] == 0x78 &&
        bytes[i + 6] == 0x69 &&
        bytes[i + 7] == 0x66;
    if (isExif) return null;
    final isStartOfFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isStartOfFrame) return _positive(u16(i + 7), u16(i + 5));
    i += 2 + segmentLength;
  }
  return null;
}

({int width, int height})? _positive(int width, int height) =>
    width > 0 && height > 0 ? (width: width, height: height) : null;

/// תמונה מזיכרון שמפוענחת ברוחב שבו היא מוצגת, ולא ברזולוציה המלאה.
///
/// סריקת עמוד של 2000×2800 תופסת 22MB מפוענחת; ספר עם עשרות כאלה קרס (#5033).
/// הפריסה זהה ל-`Image` בלי מידות: [pixelWidth]×[pixelHeight] פיקסלים לוגיים,
/// מוקטנים לאילוצים בשמירת היחס.
class DisplaySizedMemoryImage extends StatefulWidget {
  const DisplaySizedMemoryImage({
    super.key,
    required this.bytes,
    required this.pixelWidth,
    required this.pixelHeight,
    this.semanticLabel,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final int pixelWidth;
  final int pixelHeight;
  final String? semanticLabel;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<DisplaySizedMemoryImage> createState() =>
      _DisplaySizedMemoryImageState();
}

class _DisplaySizedMemoryImageState extends State<DisplaySizedMemoryImage> {
  /// null עד הפריסה הראשונה: רוחב הפענוח נקבע רק כשרוחב התצוגה ידוע.
  int? _decodeWidth;
  double _devicePixelRatio = 1;

  void _onLayoutWidth(double width) {
    final target = math.min(
      widget.pixelWidth,
      (width * _devicePixelRatio).ceil(),
    );
    // רק הגדלה: הקטנה הייתה מפענחת שוב בכל שינוי רוחב בלי לחסוך זיכרון של ממש.
    if (target <= 0 || target <= (_decodeWidth ?? 0)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && target > (_decodeWidth ?? 0)) {
        setState(() => _decodeWidth = target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = _decodeWidth;
    return _AspectSizedBox(
      pixelSize: Size(
        widget.pixelWidth.toDouble(),
        widget.pixelHeight.toDouble(),
      ),
      onLayoutWidth: _onLayoutWidth,
      child: decodeWidth == null
          ? null
          : Image(
              image: ResizeImage.resizeIfNeeded(
                decodeWidth < widget.pixelWidth ? decodeWidth : null,
                null,
                MemoryImage(widget.bytes),
              ),
              fit: BoxFit.fill,
              gaplessPlayback: true,
              semanticLabel: widget.semanticLabel,
              excludeFromSemantics: widget.semanticLabel == null,
              errorBuilder: widget.errorBuilder,
            ),
    );
  }
}

class _AspectSizedBox extends SingleChildRenderObjectWidget {
  const _AspectSizedBox({
    required this.pixelSize,
    required this.onLayoutWidth,
    super.child,
  });

  final Size pixelSize;
  final ValueChanged<double> onLayoutWidth;

  @override
  _RenderAspectSizedBox createRenderObject(BuildContext context) =>
      _RenderAspectSizedBox(pixelSize, onLayoutWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAspectSizedBox renderObject,
  ) {
    renderObject
      ..pixelSize = pixelSize
      ..onLayoutWidth = onLayoutWidth;
  }
}

/// גודל כמו של `RenderImage` עם תמונה במידות [pixelSize], עוד לפני הפענוח.
class _RenderAspectSizedBox extends RenderProxyBox {
  _RenderAspectSizedBox(this._pixelSize, this.onLayoutWidth);

  Size _pixelSize;
  ValueChanged<double> onLayoutWidth;

  set pixelSize(Size value) {
    if (value == _pixelSize) return;
    _pixelSize = value;
    markNeedsLayout();
  }

  Size _sizeFor(BoxConstraints constraints) =>
      constraints.constrainSizeAndAttemptToPreserveAspectRatio(_pixelSize);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _sizeFor(BoxConstraints.tightForFinite(height: height)).width;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _sizeFor(BoxConstraints.tightForFinite(height: height)).width;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _sizeFor(BoxConstraints.tightForFinite(width: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sizeFor(BoxConstraints.tightForFinite(width: width)).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
    child?.layout(BoxConstraints.tight(size));
    onLayoutWidth(size.width);
  }
}
