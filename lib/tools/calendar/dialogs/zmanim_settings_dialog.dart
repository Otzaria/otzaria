import 'dart:math' as math;
import 'package:otzaria/theme/app_tokens.dart';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:otzaria/tools/calendar/models/zman_definition.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

/// תוכן דיאלוג "זמנים נוספים" — טבלה קומפקטית מקובצת לפי קטגוריות של כל
/// הזמנים הזמינים. כל שורה מציגה את שם הזמן ואת זמנו ביום הנוכחי;
/// העמודה הימנית היא תיבת סימון להצגה/הסתרה בלוח, ויש כפתור מידע
/// המציג את אופן החישוב (בריחוף או בלחיצה).
class ZmanimSettingsContent extends StatelessWidget {
  const ZmanimSettingsContent({super.key});

  /// מחזיר את זמן ההגדרה ליום הנוכחי, או "—" אם אינו זמין/רלוונטי.
  static String _timeFor(ZmanDefinition def, Map<String, String> dailyTimes) {
    final t = dailyTimes[def.id];
    return (t == null || t.isEmpty) ? '—' : t;
  }

  @override
  Widget build(BuildContext context) {
    // קיבוץ הרישום לפי קטגוריה, בשמירה על סדר ההופעה.
    final categories = <String, List<ZmanDefinition>>{};
    for (final def in kZmanimRegistry) {
      categories.putIfAbsent(def.category, () => []).add(def);
    }

    // גודל רספונסיבי: 440x540 כתקרה בדסקטופ, ובמסכים צרים מצטמצם לפי
    // המקום הזמין. מנכים את ה-chrome של ה-AlertDialog (insetPadding +
    // contentPadding, וגם כותרת/כפתורים בציר האנכי) כדי למנוע overflow.
    final media = MediaQuery.sizeOf(context);
    // math.max מגן מפני ערך שלילי במסכים צרים/חלון מוקטן (אחרת SizedBox
    // היה מקבל מידה שלילית).
    final width = math.min(440.0, math.max(0.0, media.width - 128));
    final height = math.min(540.0, math.max(0.0, media.height - 200));

    return SizedBox(
      width: width,
      height: height,
      child: BlocBuilder<CalendarCubit, CalendarState>(
        buildWhen: (a, b) =>
            a.enabledZmanim != b.enabledZmanim || a.dailyTimes != b.dailyTimes,
        builder: (context, state) {
          final dailyTimes = state.dailyTimes;
          // סדר הרישום — שובר-שוויון יציב לזמני תאריך עברי (קידוש לבנה),
          // שמחרוזת התצוגה שלהם אינה ברת-מיון כרונולוגי.
          final registryOrder = {
            for (final (i, d) in kZmanimRegistry.indexed) d.id: i,
          };
          // מיון כל קטגוריה לפי זמן היום (זמן חסר — בסוף). זמני תאריך עברי
          // אינם ברי-מיון לקסיקוגרפי ולכן ממוינים לפי סדר הרישום.
          int byTime(ZmanDefinition a, ZmanDefinition b) {
            final ta = dailyTimes[a.id] ?? '';
            final tb = dailyTimes[b.id] ?? '';
            if (ta.isEmpty && tb.isEmpty) {
              return (registryOrder[a.id] ?? 0).compareTo(
                registryOrder[b.id] ?? 0,
              );
            }
            if (ta.isEmpty) return 1;
            if (tb.isEmpty) return -1;
            final aClock = isClockTime(ta);
            final bClock = isClockTime(tb);
            if (aClock && bClock) return ta.compareTo(tb);
            if (aClock != bClock) return aClock ? -1 : 1;
            return (registryOrder[a.id] ?? 0).compareTo(
              registryOrder[b.id] ?? 0,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SourceCredit(),
              const _TableHeader(),
              const Divider(height: 1),
              Expanded(
                child: Scrollbar(
                  child: ListView(
                    primary: true,
                    // מרווח בקצה (שמאל ב-RTL) כדי שסרגל הגלילה לא יכסה
                    // את אייקוני המידע.
                    padding: const EdgeInsetsDirectional.only(end: 14),
                    children: [
                      for (final entry in categories.entries) ...[
                        _CategoryHeader(title: entry.key),
                        for (final (i, def) in ([
                          ...entry.value,
                        ]..sort(byTime)).indexed)
                          _ZmanTableRow(
                            definition: def,
                            enabled: state.enabledZmanim.contains(def.id),
                            timeLabel: _timeFor(def, dailyTimes),
                            striped: i.isOdd,
                            onChanged: (value) => context
                                .read<CalendarCubit>()
                                .setZmanEnabled(def.id, value),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// שורת קרדיט למקור הזמנים — מציגה "לוח עתים לבינה" כקישור לאתר.
class _SourceCredit extends StatelessWidget {
  const _SourceCredit();

  static final Uri _url = Uri.parse('https://itimlabina.co.il');

  Future<void> _open() async {
    if (await canLaunchUrl(_url)) {
      await launchUrl(_url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: _open,
        borderRadius: AppTokens.borderRadiusAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text.rich(
            TextSpan(
              text: 'חלק ניכר מהמידע על הזמנים באדיבות ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              children: [
                TextSpan(
                  text: 'לוח עתים לבינה',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// שורת כותרת העמודות של הטבלה.
class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('הצג', style: style, textAlign: TextAlign.center),
          ),
          Expanded(child: Text('זמן', style: style)),
          SizedBox(
            width: 96,
            child: Text('היום', style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;
  const _CategoryHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// שורת זמן בטבלה — קומפקטית, עם רקע זברה לסירוגין.
class _ZmanTableRow extends StatelessWidget {
  final ZmanDefinition definition;
  final bool enabled;
  final String timeLabel;
  final bool striped;
  final ValueChanged<bool> onChanged;

  const _ZmanTableRow({
    required this.definition,
    required this.enabled,
    required this.timeLabel,
    required this.striped,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      // רקע זברה: שורה מודגשת מקבלת את גוון ה-surface הגבוה ביותר, ושאר
      // השורות שקופות (על רקע הדיאלוג).
      color: striped ? scheme.surfaceContainerHighest : Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!enabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              // עמודה ימנית — תיבת סימון (V / ביטול)
              SizedBox(
                width: 36,
                child: Checkbox(
                  value: enabled,
                  onChanged: (v) => onChanged(v ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              Expanded(
                child: Text(
                  definition.fullName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  timeLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: timeLabel == '—'
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
              ),
              _ZmanInfoButton(
                name: definition.fullName,
                explanation: definition.explanation,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// כפתור מידע — מציג את הסבר החישוב בריחוף (Tooltip) ובלחיצה (חלונית).
class _ZmanInfoButton extends StatelessWidget {
  final String name;
  final String explanation;
  final Color color;

  const _ZmanInfoButton({
    required this.name,
    required this.explanation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: explanation,
      textAlign: TextAlign.right,
      waitDuration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 320),
      textStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: IconButton(
        icon: Icon(FluentIcons.info_24_regular, size: 16, color: color),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        onPressed: () => showSingleActionDialog(
          context: context,
          title: name,
          content: explanation,
          confirmText: 'הבנתי',
        ),
      ),
    );
  }
}

/// עוזר להצגת הדיאלוג. ה-context חייב לכלול CalendarCubit ב-tree.
Future<void> showZmanimSettingsDialog(BuildContext context) {
  final cubit = context.read<CalendarCubit>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const AppDialog.singleAction(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.clock_24_regular),
            SizedBox(width: 8),
            Text('זמנים נוספים'),
          ],
        ),
        customContent: ZmanimSettingsContent(),
        confirmText: 'סגור',
      ),
    ),
  );
}
