// lib/widgets/dialogs/dialogs_exports.dart
//
// Barrel export לכל דיאלוגי האפליקציה.
//
// ─── דיאלוגי אישור/ביטול ─────────────────────────────────────────────────────
// [AppDialog.singleAction] / [showSingleActionDialog] → app_dialogs.dart
// [AppDialog.twoActions]   / [showTwoActionsDialog]   → app_dialogs.dart
// [AppDialog.warning]      / [showWarningDialog]      → app_dialogs.dart
//   שימוש: דיאלוגים M3 עם ניווט מקלדת והדגשת פוקוס.
//
// [ConfirmationDialog] / [showConfirmationDialog]     → confirmation_dialog.dart
//   wrapper דק מעל AppDialog — תומך ב-[isDangerous].
//
// ─── דיאלוגי קלט ─────────────────────────────────────────────────────────────
// [InputDialog] / [showInputDialog]                   → input_dialog.dart
//
// ─── דיאלוגי הגדרות ──────────────────────────────────────────────────────────
// [GenericSettingsDialog]                             → generic_settings_dialog.dart
//
// ─── דיאלוגי בחירה ───────────────────────────────────────────────────────────
// [SelectionDialog]                                   → selection_dialog.dart
//
// ─── מיכל לדיאלוגים מורכבים ──────────────────────────────────────────────────
// [AppCustomContentDialog]                            → reusable_items_dialog.dart
//   שימוש: מסכים מורכבים כדיאלוג (לוח שנה, הערות, היסטוריה).
//          תומך ב-actions, onConfirm, Escape אוטומטי.
//
export 'confirmation_dialog.dart';
export 'app_dialogs.dart';
export 'details_info_section.dart';
export 'input_dialog.dart';
export 'selection_dialog.dart';
export 'reusable_items_dialog.dart';
