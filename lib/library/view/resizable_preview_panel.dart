import 'package:flutter/material.dart';
import 'package:otzaria/widgets/resizable_drag_handle.dart';

/// פאנל עם אפשרות לשנות גודל באמצעות גרירה
class ResizablePreviewPanel extends StatefulWidget {
  final Widget child;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;

  const ResizablePreviewPanel({
    super.key,
    required this.child,
    this.initialWidth = 400,
    this.minWidth = 100,
    this.maxWidth = 800,
  });

  @override
  State<ResizablePreviewPanel> createState() => _ResizablePreviewPanelState();
}

class _ResizablePreviewPanelState extends State<ResizablePreviewPanel> {
  late double _width;
  bool _isResizing = false;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
  }

  @override
  void didUpdateWidget(ResizablePreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון הרוחב כשהחלון משתנה (אבל רק אם לא בתהליך גרירה)
    if (!_isResizing && widget.initialWidth != oldWidget.initialWidth) {
      setState(() {
        _width = widget.initialWidth.clamp(widget.minWidth, widget.maxWidth);
      });
    }
    // עדכון המקסימום והמינימום
    if (widget.maxWidth != oldWidget.maxWidth ||
        widget.minWidth != oldWidget.minWidth) {
      setState(() {
        _width = _width.clamp(widget.minWidth, widget.maxWidth);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Stack(
        children: [
          // תוכן הפאנל
          widget.child,
          // אזור גרירה על המסגרת הימנית
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: ResizableDragHandle(
              isVertical: true,
              showDivider: false,
              onDragStart: () => setState(() => _isResizing = true),
              onDragDelta: (delta) {
                setState(() {
                  // כיוון הפוך - גרירה שמאלה מגדילה, ימינה מקטינה
                  _width = (_width + delta).clamp(
                    widget.minWidth,
                    widget.maxWidth,
                  );
                });
              },
              onDragEnd: () => setState(() => _isResizing = false),
            ),
          ),
        ],
      ),
    );
  }
}
