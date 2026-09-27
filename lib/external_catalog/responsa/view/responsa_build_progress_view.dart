import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_build_service.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';

/// שורה לתצוגה: תבנית עברית לתרגום, והערכים שלה.
typedef ResponsaBuildLine = ({String template, Map<String, Object?> args});

/// רק ממה שנמדד: המכנה הוא מספר הצמתים בבנייה הקודמת. בבנייה ראשונה מוצגות
/// קטגוריות בלי הערכת זמן, כי הן שונות מאוד בגודלן.
class ResponsaBuildStatus {
  final ResponsaBuildLine headline;

  /// החלק שהושלם, או `null` כשאינו ידוע (סרגל בלתי קצוב).
  final double? fraction;

  /// הזמן שנותר, או `null` כשאין בסיס להערכה.
  final Duration? remaining;

  const ResponsaBuildStatus._({
    required this.headline,
    this.fraction,
    this.remaining,
  });

  /// מתחת לזה ההערכה מבוססת על מעט מדי: דקות ההתחלה כוללות את ההרחבה
  /// הראשונה של העץ, שאיטית משאר הסריקה.
  static const Duration _settle = Duration(seconds: 10);

  /// כמה מעבר למכנה עוד נחשב "אותו עץ". מהדורה אחרת, או ספרים שנוספו,
  /// יכולים לעבור אותו; משם הוא כבר אינו מכנה.
  static const double _overshoot = 1.05;

  factory ResponsaBuildStatus.of(
    ResponsaBuildProgress progress, {
    int? expectedNodes,
    Duration scanElapsed = Duration.zero,
  }) {
    final scanned = progress.scannedNodes;
    switch (progress.stage) {
      case ResponsaBuildStage.starting:
        return const ResponsaBuildStatus._(
          headline: (template: 'מתחבר לפרויקט השו"ת...', args: {}),
        );
      case ResponsaBuildStage.classifying:
        return ResponsaBuildStatus._(
          headline: (
            template: 'מזהה ספרים מתוך {nodes} רשומות...',
            args: {'nodes': grouped(scanned)},
          ),
        );
      case ResponsaBuildStage.done:
        return const ResponsaBuildStatus._(
          headline: (template: 'הקטלוג נבנה', args: {}),
          fraction: 1,
        );
      case ResponsaBuildStage.failed:
        return const ResponsaBuildStatus._(
          headline: (template: 'הבנייה נכשלה', args: {}),
        );
      case ResponsaBuildStage.scanning:
        break;
    }

    final total = expectedNodes ?? 0;
    if (total > 0 && scanned <= total * _overshoot) {
      final fraction = (scanned / total).clamp(0.0, 0.99);
      Duration? remaining;
      if (scanElapsed >= _settle && scanned > 0 && scanned < total) {
        final seconds = scanElapsed.inSeconds * (total - scanned) / scanned;
        // עיגול לחמש שניות: הקצב משתנה בין ענפים, ומספר שקופץ בכל
        // שנייה נראה כמו ניחוש — וזה מה שהוא ברזולוציה הזו.
        remaining = Duration(
          seconds: (seconds.clamp(0, double.infinity) / 5).ceil() * 5,
        );
      }
      return ResponsaBuildStatus._(
        headline: (
          template: 'נסרקו {nodes} מתוך כ-{total} רשומות',
          args: {'nodes': grouped(scanned), 'total': grouped(total)},
        ),
        fraction: fraction,
        remaining: remaining,
      );
    }

    final sections = progress.sectionsTotal;
    if (sections > 0) {
      final done = progress.sectionsDone;
      return ResponsaBuildStatus._(
        headline: (
          template: 'נסרקו {nodes} רשומות · קטגוריה {current} מתוך {sections}',
          args: {
            'nodes': grouped(scanned),
            'current': (done + 1).clamp(1, sections),
            'sections': sections,
          },
        ),
        fraction: done / sections,
      );
    }

    return ResponsaBuildStatus._(
      headline: (
        template: 'נסרקו {nodes} רשומות...',
        args: {'nodes': grouped(scanned)},
      ),
    );
  }

  /// שורת הפירוט שמתחת לסרגל.
  ResponsaBuildLine detail(Duration elapsed) {
    final percent = fraction == null ? null : (fraction! * 100).floor();
    return switch ((percent, remaining)) {
      (final int percent, final Duration remaining) => (
        template: '{percent}% · עברו {elapsed} · נותרו כ-{remaining}',
        args: {
          'percent': percent,
          'elapsed': clock(elapsed),
          'remaining': clock(remaining),
        },
      ),
      (final int percent, null) => (
        template: '{percent}% · עברו {elapsed}',
        args: {'percent': percent, 'elapsed': clock(elapsed)},
      ),
      _ => (template: 'עברו {elapsed}', args: {'elapsed': clock(elapsed)}),
    };
  }

  /// מספר עם מפריד אלפים. `1251889` ← `1,251,889`.
  static String grouped(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  /// משך כשעון: `4:05`, ומעל שעה `1:04:05`.
  static String clock(Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    final seconds = duration.inSeconds % 60;
    final minutes = duration.inMinutes % 60;
    final hours = duration.inHours;
    return hours > 0
        ? '$hours:${two(minutes)}:${two(seconds)}'
        : '$minutes:${two(seconds)}';
  }
}

/// השעון מתעדכן כל שנייה גם בלי הודעת התקדמות: ענף גדול עובר שניות בלי
/// הודעה, ושעון שעומד נראה כמו תקיעה.
class ResponsaBuildProgressView extends StatefulWidget {
  final ResponsaBuildProgress progress;

  /// מספר הצמתים בבנייה הקודמת, אם יש.
  final int? expectedNodes;

  const ResponsaBuildProgressView({
    super.key,
    required this.progress,
    this.expectedNodes,
  });

  @override
  State<ResponsaBuildProgressView> createState() =>
      _ResponsaBuildProgressViewState();
}

class _ResponsaBuildProgressViewState extends State<ResponsaBuildProgressView> {
  final Stopwatch _total = Stopwatch()..start();

  /// נמדד מתחילת הסריקה ולא מתחילת הבנייה: העלאת בר אילן ופתיחת חלון
  /// העיון אינן חלק מקצב הסריקה, והכללתן הייתה מנפחת את ההערכה.
  final Stopwatch _scan = Stopwatch();
  late final Timer _tick;

  /// הסרגל אינו חוזר אחורה. כשהסריקה עוברת את המכנה של הבנייה הקודמת
  /// ההתקדמות עוברת לספירת קטגוריות, שהיא בדרך כלל נמוכה יותר.
  double _shown = 0;

  @override
  void initState() {
    super.initState();
    _syncScanClock();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ResponsaBuildProgressView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncScanClock();
  }

  void _syncScanClock() {
    final scanning = widget.progress.stage == ResponsaBuildStage.scanning;
    if (scanning && !_scan.isRunning) _scan.start();
    if (!scanning && _scan.isRunning) _scan.stop();
  }

  double? _monotonic(double? fraction) {
    if (fraction == null) return null;
    if (fraction > _shown) _shown = fraction;
    return _shown;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ResponsaBuildStatus.of(
      widget.progress,
      expectedNodes: widget.expectedNodes,
      scanElapsed: _scan.elapsed,
    );
    final detail = status.detail(_total.elapsed);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _monotonic(status.fraction),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 6),
          Text(
            context.settingsText(detail.template, args: detail.args),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
