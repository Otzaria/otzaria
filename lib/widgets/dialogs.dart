// lib/widgets/dialogs.dart
//
// Barrel export לכל דיאלוגי האפליקציה.
//
// ─── דיאלוגי אישור/ביטול ─────────────────────────────────────────────────────
// [ConfirmationDialog] / [showConfirmationDialog]     → confirmation_dialog.dart
//   שימוש: דיאלוג עם [isDangerous], [confirmColor], הדגשת פוקוס.
//
// [SingleActionDialog] / [showSingleActionDialog]     → dialogs/app_dialogs.dart
// [TwoActionsDialog]   / [showTwoActionsDialog]       → dialogs/app_dialogs.dart
// [WarningDialog]      / [showWarningDialog]          → dialogs/app_dialogs.dart
//   שימוש: דיאלוגים M3 FilledButton לפעולות כלליות.
//
// ─── דיאלוגי קלט ─────────────────────────────────────────────────────────────
// [InputDialog] / [showInputDialog]                   → input_dialog.dart
//
// ─── דיאלוגי הגדרות ──────────────────────────────────────────────────────────
// [GenericSettingsDialog]                             → generic_settings_dialog.dart
//
// ─── דיאלוגי בחירה ───────────────────────────────────────────────────────────
// [SelectionDialog]                                   → selection_dialog.dart
// [MultiSelectionDialog]                              → multi_selection_dialog.dart
//
// ─── מיכל כללי ───────────────────────────────────────────────────────────────
// [ReusableItemsDialog]                               → reusable_items_dialog.dart

export 'confirmation_dialog.dart';
export 'dialogs/app_dialogs.dart';
export 'input_dialog.dart';
export 'generic_settings_dialog.dart';
export 'selection_dialog.dart';
export 'multi_selection_dialog.dart';
