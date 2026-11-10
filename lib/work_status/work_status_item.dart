import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// [awaitingInput] — אין עבודה רצה, הפריט מחכה להחלטת המשתמש (בלי טבעת התקדמות).
enum WorkStatusKind { running, failed, cancelled, awaitingInput }

/// לחצן פעולה בשורת הפעולות של פריט חיווי; [emphasized] מציג אותו כלחוץ
/// (tonal) — למצב פעיל של פעולת toggle.
class WorkStatusAction {
  final String label;
  final IconData icon;
  final String? tooltip;
  final bool emphasized;
  final VoidCallback onPressed;

  const WorkStatusAction({
    required this.label,
    required this.icon,
    this.tooltip,
    this.emphasized = false,
    required this.onPressed,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkStatusAction &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          icon == other.icon &&
          tooltip == other.tooltip &&
          emphasized == other.emphasized &&
          onPressed == other.onPressed;

  @override
  int get hashCode => Object.hash(label, icon, tooltip, emphasized, onPressed);
}

class WorkStatusItem {
  final String id;
  final String title;
  final String message;
  final String? detail;
  final double? progress;
  final WorkStatusKind kind;

  /// פעולה בלחיצה על החיווי. פריט ללא ערך אינו לחיץ.
  final VoidCallback? onTap;

  /// לחצני פעולה המוצגים מתחת לפרטי הפריט (רק בפריט הראשי).
  final List<WorkStatusAction> actions;

  /// משך שאחריו הפריט יורד מעצמו; `null` = נשאר עד סגירה ידנית.
  final Duration? autoDismissAfter;

  /// שם קצר לגלולה בשורת הכותרת. `null` = אין גלולה: סגירת הכרטיס מסתירה את
  /// הפריט, והוא אינו מצטמצם.
  final String? chipLabel;

  /// משך שאחריו הכרטיס מצטמצם לגלולה ([chipLabel]) מעצמו; `null` = נשאר פתוח
  /// עד סגירה ידנית (פריט שנכשל או ממתין להחלטה).
  final Duration? collapseAfter;

  const WorkStatusItem({
    required this.id,
    required this.title,
    required this.message,
    this.detail,
    this.progress,
    this.kind = WorkStatusKind.running,
    this.onTap,
    this.actions = const [],
    this.autoDismissAfter,
    this.chipLabel,
    this.collapseAfter,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkStatusItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          message == other.message &&
          detail == other.detail &&
          progress == other.progress &&
          kind == other.kind &&
          onTap == other.onTap &&
          listEquals(actions, other.actions) &&
          autoDismissAfter == other.autoDismissAfter &&
          chipLabel == other.chipLabel &&
          collapseAfter == other.collapseAfter;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      message.hashCode ^
      detail.hashCode ^
      progress.hashCode ^
      kind.hashCode ^
      onTap.hashCode ^
      Object.hashAll(actions) ^
      autoDismissAfter.hashCode ^
      chipLabel.hashCode ^
      collapseAfter.hashCode;
}
