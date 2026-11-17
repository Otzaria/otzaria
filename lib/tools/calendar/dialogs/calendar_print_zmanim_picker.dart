import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_options.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/models/zman_definition.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/app_scrollbar.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

/// בחירת זמני היום שיודפסו בדפי לוח השנה, בדיאלוג ההדפסה.
///
/// [selection] `null` = ברירת המחדל של התצוגה (ראו [CalendarPrintZmanimStore]).
/// אחרת זה הסט שנבחר: הזמנים האלה מודפסים במקום ברירת המחדל, כמו שחגים
/// ואירועים אישיים מודפסים בתאים.
///
/// הרשימה מוצגת תמיד: בברירת מחדל מסומנים בה [defaultSelection], כלומר מה
/// שיודפס בפועל, ולחיצה על תיבה עוברת לבחירה אישית שמתחילה מהם.
class CalendarPrintZmanimPicker extends StatefulWidget {
  final CalendarView view;
  final Set<String> defaultSelection;
  final Set<String>? selection;
  final ValueChanged<Set<String>?> onChanged;

  const CalendarPrintZmanimPicker({
    super.key,
    required this.view,
    this.defaultSelection = const {},
    required this.selection,
    required this.onChanged,
  });

  @override
  State<CalendarPrintZmanimPicker> createState() =>
      _CalendarPrintZmanimPickerState();
}

class _CalendarPrintZmanimPickerState extends State<CalendarPrintZmanimPicker> {
  final ScrollController _scroll = ScrollController();

  /// מפתח לכל שורה, כדי לגלול אל הראשונה שמסומנת.
  final Map<String, GlobalKey> _rowKeys = {
    for (final def in kZmanimRegistry) def.id: GlobalKey(),
  };

  /// הרישום מקובץ לפי קטגוריה, בסדר ההופעה.
  static final Map<String, List<ZmanDefinition>> _byCategory = () {
    final categories = <String, List<ZmanDefinition>>{};
    for (final def in kZmanimRegistry) {
      categories.putIfAbsent(def.category, () => []).add(def);
    }
    return categories;
  }();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealChecked());
  }

  @override
  void didUpdateWidget(CalendarPrintZmanimPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // הדלקת המתג: הרשימה מופיעה, וגוללת אל הזמנים המסומנים.
    if (oldWidget.selection == null && widget.selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealChecked());
    }
  }

  /// גוללת אל השורה המסומנת הראשונה, כדי שהסימונים יהיו גלויים בפתיחה.
  void _revealChecked() {
    if (!mounted) return;
    for (final defs in _byCategory.values) {
      for (final def in defs) {
        if (!_shown.contains(def.id)) continue;
        // גוללים רק את הרשימה (לא את הדיאלוג שמסביבה), ולכן לא
        // Scrollable.ensureVisible שגולל את כל האבות.
        final row = _rowKeys[def.id]?.currentContext?.findRenderObject();
        final viewport = row == null ? null : RenderAbstractViewport.of(row);
        if (row != null && _scroll.hasClients) {
          final target = viewport!.getOffsetToReveal(row, 0.1).offset;
          _scroll.jumpTo(
            target.clamp(
              _scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
        return;
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _custom => widget.selection != null;

  String get _defaultHint => switch (widget.view) {
    CalendarView.month => 'בלי זמנים בתאי החודש: חגים ואירועים בלבד',
    CalendarView.week => 'זריחה ושקיעה בכל יום',
    CalendarView.day => 'הזמנים שמוצגים בלוח',
  };

  /// מה שמסומן ברשימה: הבחירה האישית, או ברירת המחדל כשלא נבחר דבר.
  Set<String> get _shown => widget.selection ?? widget.defaultSelection;

  void _toggle(String id, bool value) {
    final next = {..._shown};
    value ? next.add(id) : next.remove(id);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _shown;
    final max = maxPrintedZmanim(widget.view);
    final full = max != null && selected.length >= max;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // מתג: כבוי = ברירת המחדל של התצוגה (בלי רשימה); דלוק = בחירה אישית.
        SettingsSwitchTile(
          icon: FluentIcons.clock_24_regular,
          title: 'בחירת זמני יום להדפסה',
          subtitle: _custom ? null : _defaultHint,
          value: _custom,
          onChanged: (on) =>
              widget.onChanged(on ? {...widget.defaultSelection} : null),
        ),
        if (_custom) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  max == null
                      ? 'נבחרו ${selected.length}'
                      : 'נבחרו ${selected.length} מתוך $max',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: full ? cs.error : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (_custom)
                ActionButton.ghost(
                  text: 'נקה בחירה',
                  onPressed: selected.isEmpty
                      ? null
                      : () => widget.onChanged({}),
                ),
            ],
          ),
          if (max != null && selected.length > max)
            Text(
              'יש לצמצם את הבחירה לכל היותר ל־$max זמנים לפני ההדפסה.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          SizedBox(
            height: 240,
            child: AppCard(
              padding: EdgeInsets.zero,
              child: AppScrollbar(
                controller: _scroll,
                // כל 98 השורות נבנות מראש (לא עצלתיים): הגלילה אל הסימונים
                // זקוקה להקשר של השורה, והעלות זניחה.
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSM,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in _byCategory.entries) ...[
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: AppTokens.spaceSM,
                            bottom: AppTokens.space2XS,
                          ),
                          child: Text(
                            entry.key,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.primary,
                            ),
                          ),
                        ),
                        for (final def in entry.value)
                          _ZmanRow(
                            key: _rowKeys[def.id],
                            definition: def,
                            checked: selected.contains(def.id),
                            enabled: selected.contains(def.id) || !full,
                            onChanged: (v) => _toggle(def.id, v),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.view == CalendarView.month)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSM),
              child: Text(
                'בעמוד לרוחב נכנסים פחות זמנים בתא. לזמנים רבים בחרו בתצוגת שבוע או יום.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ZmanRow extends StatelessWidget {
  final ZmanDefinition definition;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ZmanRow({
    super.key,
    required this.definition,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? () => onChanged(!checked) : null,
      borderRadius: AppTokens.borderRadiusAll,
      child: Row(
        children: [
          Checkbox(
            value: checked,
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Expanded(
            child: Text(
              definition.fullName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
