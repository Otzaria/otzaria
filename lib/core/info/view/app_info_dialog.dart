import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/core/info/info_topic.dart';
import 'package:otzaria/core/info/view/info_section_fields.dart';
import 'package:otzaria/core/messages/messages_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// מציג את דוח [AppInfoReport] בפופאפ קטן ומעוצב.
Future<void> showAppInfoDialog(
  BuildContext context,
  AppInfoReport report,
) => showSingleActionDialog(
  context: context,
  title: report.topic.title,
  confirmText: 'סגירה',
  customContent: AppInfoDialogContent(report: report),
);

/// תוכן פופאפ המידע: מקטע לכל נושא, ומתחתיו ה-JSON הגולמי להעתקה.
class AppInfoDialogContent extends StatefulWidget {
  const AppInfoDialogContent({super.key, required this.report});

  final AppInfoReport report;

  @override
  State<AppInfoDialogContent> createState() => _AppInfoDialogContentState();
}

class _AppInfoDialogContentState extends State<AppInfoDialogContent> {
  bool _showRawJson = false;

  String get _prettyJson =>
      const JsonEncoder.withIndent('  ').convert(widget.report.toJson());

  Future<void> _copyJson() async {
    try {
      await Clipboard.setData(ClipboardData(text: _prettyJson));
      UiSnack.show(CommonMessages.textCopied);
    } catch (_) {
      UiSnack.showError(CommonMessages.clipboardCopyError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = widget.report.sections;
    // AlertDialog משאיר לתוכן 80px פחות מרוחב המסך (insetPadding); רוחב קבוע
    // גדול מזה גורם ל-overflow אופקי במסך צר.
    final width = math.min(
      420.0,
      MediaQuery.of(context).size.width - 96,
    );

    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(cs),
            const SizedBox(height: 12),
            for (final topic in widget.report.topic.sections)
              if (sections[topic.slug] case final data?) ...[
                _InfoSectionCard(topic: topic, data: data),
                const SizedBox(height: 10),
              ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionButton.ghost(
                text: _showRawJson ? 'הסתר JSON' : 'הצג JSON',
                onPressed: () => setState(() => _showRawJson = !_showRawJson),
              ),
            ),
            if (_showRawJson)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppSurfaces.panelSection(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  _prettyJson,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Row(
      children: [
        Icon(FluentIcons.info_24_regular, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            InfoValueFormat.dateTime(widget.report.generatedAt),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        IconButton(
          tooltip: 'העתק JSON',
          visualDensity: VisualDensity.compact,
          icon: const Icon(FluentIcons.copy_24_regular, size: 18),
          onPressed: _copyJson,
        ),
      ],
    );
  }
}

/// כרטיס מקטע — כותרת הנושא ושורות התווית/ערך שלו.
class _InfoSectionCard extends StatelessWidget {
  const _InfoSectionCard({required this.topic, required this.data});

  final InfoTopic topic;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final error = data['error'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppSurfaces.panelSection(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            topic.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 6),
          if (error != null)
            _InfoRow(label: 'שגיאה באיסוף', value: '$error')
          else ...[
            for (final field in InfoSectionFields.of(topic))
              if (data.containsKey(field.key))
                _InfoRow(
                  label: field.label,
                  value: field.format(data[field.key], data),
                  isLtr: field.isLtr,
                  isBlock: field.isBlock,
                ),
            ..._buildLists(context),
          ],
        ],
      ),
    );
  }

  /// מספר שמות הקבצים שמוצגים בפופאפ לכל תיקייה. הרשימה המלאה (עד `files=`)
  /// נשארת ב-JSON — עשרות שורות לכל תיקייה היו מטביעות את שאר הדוח.
  static const int _maxFileNamesPerFolder = 10;

  List<Widget> _buildLists(BuildContext context) {
    if (topic == InfoTopic.folders) {
      final folders = (data['folders'] as List?) ?? const [];
      if (folders.isEmpty) {
        return const [
          _InfoRow(label: 'תיקיות', value: 'לא הוגדרו תיקיות ספרים אישיים'),
        ];
      }
      return [
        const _SubHeader('התיקיות המוגדרות'),
        for (final folder in folders.whereType<Map>())
          _FolderEntryTile(
            folder: folder,
            maxFileNames: _maxFileNamesPerFolder,
          ),
      ];
    }

    if (topic == InfoTopic.plugins) {
      final plugins = (data['installed'] as List?) ?? const [];
      if (plugins.isEmpty) return const [];
      return [
        const _SubHeader('התוספים המותקנים'),
        for (final plugin in plugins.whereType<Map>())
          _InfoRow(
            label: '${plugin['id']}',
            value: InfoValueFormat.pluginVersion(plugin),
            isLtr: true,
            labelIsLtr: true,
          ),
      ];
    }

    if (topic == InfoTopic.errors) {
      final recent = (data['recent'] as List?) ?? const [];
      if (recent.isEmpty) {
        return const [_InfoRow(label: 'רשומות אחרונות', value: 'אין שגיאות')];
      }
      return [
        const _SubHeader('רשומות אחרונות'),
        for (final entry in recent.whereType<Map>())
          _ErrorEntryTile(entry: entry),
      ];
    }

    return const [];
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// שורת תווית/ערך. התווית בתחילת השורה, הערך בסופה. עם [isBlock] — התווית
/// בשורה משלה והערך מתחתיה ברוחב מלא.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isLtr = false,
    this.labelIsLtr = false,
    this.isBlock = false,
  });

  final String label;
  final String value;
  final bool isLtr;
  final bool labelIsLtr;
  final bool isBlock;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);

    if (isBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: labelStyle),
            SelectableText(
              value,
              textDirection: isLtr ? TextDirection.ltr : null,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      // שתי עמודות בעלות flex קבוע — Flexible רפוי היה מותיר את הערך צמוד
      // לתווית עם רווח מבוזבז בקצה השורה במקום ליישר את הערכים לעמודה אחת.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: labelStyle,
              textDirection: labelIsLtr ? TextDirection.ltr : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              textDirection: isLtr ? TextDirection.ltr : null,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// תיקיית ספרים אישיים בודדת: הנתיב, תקציר הקבצים, ושמות הקבצים הראשונים.
class _FolderEntryTile extends StatelessWidget {
  const _FolderEntryTile({required this.folder, required this.maxFileNames});

  final Map<dynamic, dynamic> folder;
  final int maxFileNames;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final files = (folder['files'] as List?)?.whereType<Map>().toList() ?? [];
    final shown = files.take(maxFileNames).toList();
    // ההפרש נמדד מול הספירה המלאה ולא מול אורך הרשימה: `files=` כבר קיצץ
    // אותה, ו"ועוד 0" היה מסתיר קבצים שקיימים בתיקייה. כש-`files=0` אין
    // רשימה בכלל, והספירה שבשורת התקציר כבר אומרת את מה ש"ועוד" היה אומר.
    final fileCount = folder['fileCount'];
    final remaining = (shown.isNotEmpty && fileCount is int)
        ? fileCount - shown.length
        : 0;
    final types = InfoValueFormat.folderTypes(folder);
    final scanError = folder['scanError'];

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            '${folder['path']}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          Text(
            InfoValueFormat.folderSummary(folder),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          if (types.isNotEmpty)
            Text(
              types,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          if (scanError != null)
            Text(
              'שגיאת סריקה: $scanError',
              style: TextStyle(fontSize: 11, color: cs.error),
            ),
          for (final file in shown)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2, start: 8),
              child: SelectableText(
                '${file['name']}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2, start: 8),
              child: Text(
                'ועוד ${InfoValueFormat.count(remaining)}…',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// רשומת שגיאה בודדת: כותרת, זמן, והודעה מקוצרת.
class _ErrorEntryTile extends StatelessWidget {
  const _ErrorEntryTile({required this.entry});

  final Map<dynamic, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timestamp = InfoValueFormat.dateTimeOrDash(entry['timestamp']);
    final message = '${entry['message'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entry['title']}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                timestamp,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                message,
                maxLines: 3,
                style: TextStyle(fontSize: 11, color: cs.error),
              ),
            ),
        ],
      ),
    );
  }
}
