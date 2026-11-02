// lib/widgets/dialogs/dialogs_exports.dart
//
// Barrel export לכל דיאלוגי האפליקציה.
//
// ─── דיאלוגי אישור/ביטול ─────────────────────────────────────────────────────
// [AppDialog.singleAction] / [showSingleActionDialog] → app_dialogs.dart
// [AppDialog.twoActions]   / [showTwoActionsDialog]   → app_dialogs.dart
// [AppDialog.warning]      / [showWarningDialog]      → app_dialogs.dart
//   שימוש: דיאלוגים M3 עם ניווט מקלדת והדגשת פוקוס. כולם מעל AppDialogFrame
//   (app_dialog_frame.dart): רצועת כותרת, תג אייקון וגודל (AppDialogSize).
// [showChoiceDialog]                                  → app_dialogs.dart
//   שימוש: בחירה בין כמה פעולות שוות ("טקסט / Word / ביטול").
// [runWithBlockingProgress]                           → blocking_progress_dialog.dart
//   שימוש: פעולה חוסמת ארוכה, בדיאלוג שאי אפשר לסגור.
// [showBlockingProgress]                              → blocking_progress_dialog.dart
//   שימוש: אותו דיאלוג לזרימה עם כמה נקודות יציאה; מחזיר פונקציית סגירה.
//
// [ConfirmationDialog] / [showConfirmationDialog]     → confirmation_dialog.dart
//   wrapper דק מעל AppDialog — תומך ב-[isDangerous].
//
// ─── דיאלוגי קלט ─────────────────────────────────────────────────────────────
// [InputDialog] / [showInputDialog]                   → input_dialog.dart
//
// ─── דיאלוגי בחירה ───────────────────────────────────────────────────────────
// [SelectionDialog]                                   → selection_dialog.dart
//
// ─── מיכל לדיאלוגים מורכבים ──────────────────────────────────────────────────
// [AppDialogFrame(size:)]                             → app_dialog_frame.dart
//   שימוש: טפסים (medium), רשימות וניהול (large), מסך מלא (full).
//          תומך ב-actions, onConfirm, isDirty, scrollable.
//
export 'confirmation_dialog.dart';
export 'app_dialogs.dart';
export 'dialog_teardown.dart';
export 'dialog_dismiss_guard.dart';
export 'app_dialog_header.dart';
export 'details_info_section.dart';
export 'input_dialog.dart';
export 'selection_dialog.dart';
export 'blocking_progress_dialog.dart';
