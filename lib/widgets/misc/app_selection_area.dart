import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';

/// אזור בחירת טקסט שמציג בלחיצה ימנית את תפריט ההקשר של אוצריא
/// (במקום תפריט ברירת המחדל של Flutter). לתוכן קריא כללי —
/// דיאלוגים, חלוניות וכותרות.
class AppSelectionArea extends StatefulWidget {
  const AppSelectionArea({super.key, required this.child, this.protection});

  final Widget child;

  /// הגבלת המו"ל של הטקסט שבאזור, כשהוא תוכן ספר.
  final Future<BookProtection> Function()? protection;

  @override
  State<AppSelectionArea> createState() => AppSelectionAreaState();

  static AppSelectionAreaState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<AppSelectionAreaState>();
}

class AppSelectionAreaState extends State<AppSelectionArea> {
  String? _selectedText;
  final _selectionSources = <String Function(), bool Function(Offset)>{};

  /// מקור בחירה נוסף עם בדיקת מיקום בקואורדינטות גלובליות.
  void addSelectionSource(
    String Function() source, {
    required bool Function(Offset) containsPosition,
  }) => _selectionSources[source] = containsPosition;

  void removeSelectionSource(String Function() source) =>
      _selectionSources.remove(source);

  final _protectionSources = <Future<BookProtection> Function()>{};

  /// תוכן ספר שמוצג באזור (למשל תצוגה מקדימה של קישור) רושם כאן את הגבלתו.
  void addProtectionSource(Future<BookProtection> Function() source) =>
      _protectionSources.add(source);

  void removeProtectionSource(Future<BookProtection> Function() source) =>
      _protectionSources.remove(source);

  bool get _isGuarded =>
      widget.protection != null || _protectionSources.isNotEmpty;

  Future<bool> _copyAllowed(String text) async {
    if (!_isGuarded) return true;
    var protection = BookProtection.none;
    for (final source in [?widget.protection, ..._protectionSources]) {
      protection = protection.strictest(await source());
    }
    return ensureCopyAllowed(protection, countTextSegments(text));
  }

  bool get _hasSelection =>
      _selectedText != null && _selectedText!.trim().isNotEmpty;

  String? _textToCopyAt(Offset position) {
    for (final entry in _selectionSources.entries) {
      if (entry.value(position)) {
        final text = entry.key();
        return text.trim().isEmpty ? null : text;
      }
    }
    return _hasSelection ? _selectedText : null;
  }

  Future<void> _copy(String text) async {
    if (!await _copyAllowed(text)) return;
    await Clipboard.setData(ClipboardData(text: text));
    UiSnack.show(CommonMessages.textCopiedShort);
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final useNativeTouchMenu =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: _GuardedCopyAction(this),
      },
      child: RtlSelectionShortcuts(
        child: SelectionArea(
          contextMenuBuilder: useNativeTouchMenu
              ? (context, state) =>
                    AdaptiveTextSelectionToolbar.selectableRegion(
                      selectableRegionState: state,
                    )
              : (context, _) => const SizedBox.shrink(),
          onSelectionChanged: (selection) {
            trackRtlSelection(selection?.plainText);
            // שינוי בחירה זמני בזמן priming (קיצורי RTL) — לא לעבד.
            if (rtlSelectionPriming) return;
            _selectedText = selection?.plainText;
          },
          child: AppContextMenuRegion(
            openOnLongPress: !useNativeTouchMenu,
            // לחיצה ימנית על הטקסט המסומן לא תשחרר את הבחירה (ברירת המחדל של
            // SelectableRegion ב-Windows); לחיצה מחוץ לבחירה מבטלת כרגיל.
            shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
              if (!_hasSelection) return false;
              final root = context.findRenderObject();
              if (root == null) return true;
              return clickIsOnSelectionWithinArea(
                    root: root,
                    globalPosition: globalPosition,
                    selectedText: _selectedText!,
                  ) ??
                  true;
            },
            menuBuilder: (menuContext, position) {
              final text = _textToCopyAt(position);
              return [
                AppContextMenuEntry(
                  label: 'העתק',
                  icon: FluentIcons.copy_24_regular,
                  enabled: text != null,
                  onTap: () => _copy(text!),
                ),
              ];
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// משחרר את Ctrl+X (כמו [SelectionCutFallthrough]), ובאזור עם תוכן ספר מוגן
/// מעביר את Ctrl+C דרך מגבלת ההעתקה.
class _GuardedCopyAction extends Action<CopySelectionTextIntent> {
  _GuardedCopyAction(this._area);

  final AppSelectionAreaState _area;

  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? true;

  @override
  bool isEnabled(CopySelectionTextIntent intent) {
    if (isReadOnlyCutIntent(intent)) return false;
    return callingAction?.isEnabled(intent) ?? true;
  }

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    final text = _area._selectedText;
    if (!_area._isGuarded || text == null || text.trim().isEmpty) {
      return callingAction?.invoke(intent);
    }
    _area._copy(text);
    return null;
  }
}
