import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// פס גלילה מותאם אישית ל-PDF עם track מלא
class PdfScrollbar extends StatelessWidget {
  final PdfViewerController controller;
  final ScrollbarOrientation orientation;
  final double trackThickness;
  final Color? trackColor;
  final Color? thumbColor;
  final double thumbMinSize;

  const PdfScrollbar({
    super.key,
    required this.controller,
    required this.orientation,
    this.trackThickness = 12.0,
    this.trackColor,
    this.thumbColor,
    this.thumbMinSize = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    final isVertical = orientation == ScrollbarOrientation.right ||
        orientation == ScrollbarOrientation.left;

    return PdfViewerScrollThumb(
      controller: controller,
      orientation: orientation,
      thumbSize: isVertical
          ? Size(trackThickness, thumbMinSize)
          : Size(thumbMinSize, trackThickness),
      thumbBuilder: (context, thumbSize, pageNumber, controller) {
        // פס גלילה פשוט ללא שכבות מיותרות
        return Container(
          width: isVertical ? trackThickness : thumbSize.width,
          height: isVertical ? thumbSize.height : trackThickness,
          decoration: BoxDecoration(
            color: thumbColor ?? Colors.grey.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(trackThickness / 2),
          ),
          child: isVertical
              ? Center(
                  child: Text(
                    (pageNumber ?? 1).toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// פס גלילה אופקי דינמי שמתאים את גודלו לפי יחס התוכן הנראה
///
/// שימו לב: Widget זה חייב להיות ישירות בתוך viewerOverlayBuilder של PdfViewer
/// ולא ניתן לעטוף אותו ב-widgets נוספים בגלל מגבלות של PdfViewerScrollThumb
class PdfHorizontalScrollbar extends StatelessWidget {
  // קבועים לחישוב גודל ה-thumb
  static const double _minThumbRatio = 0.15; // מינימום 15% מהמסך
  static const double _maxThumbRatio = 0.85; // מקסימום 85% מהמסך
  static const double _minZoomForNormalization = 0.5; // זום מינימלי
  static const double _zoomRangeForNormalization = 4.5; // טווח הזום (5.0 - 0.5)
  static const double _minThumbWidth = 60.0; // רוחב מינימלי בפיקסלים
  static const double _maxThumbWidthFactor = 0.95; // מקסימום 95% מהמסך

  final PdfViewerController controller;
  final double trackThickness;
  final Color? trackColor;
  final Color? thumbColor;

  const PdfHorizontalScrollbar({
    super.key,
    required this.controller,
    this.trackThickness = 8.0,
    this.trackColor,
    this.thumbColor,
  });

  @override
  Widget build(BuildContext context) {
    // נשתמש ב-MediaQuery כדי לקבל את רוחב המסך
    final screenWidth = MediaQuery.of(context).size.width;

    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, child) {
        if (!controller.isReady) {
          return const SizedBox.shrink();
        }

        // חישוב גודל ה-thumb לפי רמת הזום
        final zoom = value.zoom;

        // חישוב גודל ה-thumb לפי רמת הזום
        // ככל שהזום גדול יותר, ה-thumb קטן יותר (יש יותר תוכן לגלול)
        // נורמליזציה של הזום (בדרך כלל בין 0.5 ל-5.0)
        final normalizedZoom =
            ((zoom - _minZoomForNormalization) / _zoomRangeForNormalization)
                .clamp(0.0, 1.0);
        final thumbRatio = _maxThumbRatio -
            (normalizedZoom * (_maxThumbRatio - _minThumbRatio));

        final thumbWidth = screenWidth * thumbRatio;

        // מינימום ומקסימום לגודל ה-thumb
        final maxThumbWidth = screenWidth * _maxThumbWidthFactor;
        final clampedThumbWidth =
            thumbWidth.clamp(_minThumbWidth, maxThumbWidth);

        return PdfViewerScrollThumb(
          controller: controller,
          orientation: ScrollbarOrientation.bottom,
          thumbSize: Size(clampedThumbWidth, trackThickness),
          thumbBuilder: (context, thumbSize, pageNumber, controller) {
            return Container(
              width: thumbSize.width,
              height: trackThickness,
              decoration: BoxDecoration(
                color: thumbColor ?? Colors.grey.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(trackThickness / 2),
              ),
            );
          },
        );
      },
    );
  }
}
