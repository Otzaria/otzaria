import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/core/info/info_topic.dart';
import 'package:otzaria/core/info/view/info_section_fields.dart';
import 'package:otzaria/core/messages/messages_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/utils/file/open_in_file_manager.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// מציג את דוח [AppInfoReport] בפופאפ קטן ומעוצב.
Future<void> showAppInfoDialog(
  BuildContext context,
  AppInfoReport report,
) => showSingleActionDialog(
  context: context,
  title: report.topic.title,
  icon: report.topic.icon,
  headerBand: true,
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
      460.0,
      MediaQuery.of(context).size.width - 96,
    );

    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        child: AppSelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(cs),
              const SizedBox(height: AppTokens.spaceMD),
              for (final topic in widget.report.topic.sections)
                if (sections[topic.slug] case final data?) ...[
                  _InfoSection(topic: topic, data: data),
                  const SizedBox(height: AppTokens.spaceMD),
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
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: Text(
                    _prettyJson,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppTokens.fontSM,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    // ברוחב טלפון התאריך והכפתור לא נכנסים בשורה אחת: הכפתור יורד מתחת.
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final copyButton = TextButton.icon(
      onPressed: _copyJson,
      icon: const Icon(FluentIcons.copy_24_regular, size: 18),
      label: const Text('העתק JSON'),
    );
    final date = Row(
      children: [
        Icon(
          FluentIcons.clock_24_regular,
          size: AppTokens.fontLG,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: AppTokens.spaceSM),
        Expanded(
          child: Text(
            '${getHebrewDateFormattedAsString(widget.report.generatedAt)}'
            // LRI/PDI: בלעדיהם השעה מתהפכת לפני התאריך בתוך משפט ימני.
            ' · \u2066${InfoValueFormat.dateTime(widget.report.generatedAt)}\u2069',
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          date,
          Align(alignment: AlignmentDirectional.centerStart, child: copyButton),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: date),
        copyButton,
      ],
    );
  }
}

/// במובייל אין מנהל קבצים שאפשר לפתוח בו תיקייה, אז נתיבים נשארים טקסט.
bool get _canOpenPaths =>
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;

/// פותח נתיב מהדוח במנהל הקבצים. קובץ (כמו מסד הספרייה) נפתח דרך התיקייה
/// שמכילה אותו, כדי שלא יופעל בתוכנית ברירת המחדל שלו.
Future<void> _openInfoPath(String path) async {
  try {
    final target = FileSystemEntity.isFileSync(path)
        ? File(path).parent.path
        : path;
    if (!FileSystemEntity.isDirectorySync(target)) {
      UiSnack.showError('המיקום לא נמצא בדיסק');
      return;
    }
    await openInFileManager(target);
  } catch (_) {
    UiSnack.showError('לא ניתן לפתוח את המיקום');
  }
}

/// האייקון של נושא המידע: בכותרת הדיאלוג ובכרטיס המקטע.
extension InfoTopicIcon on InfoTopic {
  IconData get icon => switch (this) {
    InfoTopic.app => FluentIcons.app_generic_24_regular,
    InfoTopic.library => FluentIcons.library_24_regular,
    InfoTopic.folders => FluentIcons.folder_open_24_regular,
    InfoTopic.plugins => FluentIcons.puzzle_piece_24_regular,
    InfoTopic.errors => FluentIcons.error_circle_24_regular,
    InfoTopic.all => FluentIcons.info_24_regular,
  };
}

/// מקטע נושא אחד: כרטיס עם שורות התווית והערך, ומתחתיו הרשימה של הנושא
/// (תיקיות, תוספים או שגיאות) בכרטיסים משלה.
class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.topic, required this.data});

  final InfoTopic topic;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final error = data['error'];
    final rows = <Widget>[
      if (error != null)
        DetailsInfoSection(title: 'שגיאה באיסוף', value: '$error')
      else
        for (final field in InfoSectionFields.of(topic))
          if (data.containsKey(field.key))
            DetailsInfoSection(
              title: field.label,
              value: field.format(data[field.key], data),
              valueDirection: field.isLtr ? TextDirection.ltr : null,
              block: field.isBlock,
              onTap: field.isPath && _canOpenPaths && data[field.key] != null
                  ? () => _openInfoPath('${data[field.key]}')
                  : null,
              tapTooltip: 'פתיחה במנהל הקבצים',
            ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsCard(title: topic.title, icon: topic.icon, children: rows),
        if (error == null) ..._buildLists(context),
      ],
    );
  }

  /// מספר שמות הקבצים שמוצגים בפופאפ לכל תיקייה. הרשימה המלאה (עד `files=`)
  /// נשארת ב-JSON — עשרות שורות לכל תיקייה היו מטביעות את שאר הדוח.
  static const int _maxFileNamesPerFolder = 10;

  List<Widget> _buildLists(BuildContext context) {
    const gap = SizedBox(height: AppTokens.spaceMD);

    if (topic == InfoTopic.folders) {
      final folders = (data['folders'] as List?) ?? const [];
      if (folders.isEmpty) {
        return const [
          gap,
          DetailsCard(
            children: [
              DetailsInfoSection(
                title: 'תיקיות',
                value: 'לא הוגדרו תיקיות ספרים אישיים',
              ),
            ],
          ),
        ];
      }
      return [
        gap,
        const _ListHeading('התיקיות המוגדרות'),
        for (final folder in folders.whereType<Map>())
          _FolderTile(folder: folder, maxFileNames: _maxFileNamesPerFolder),
      ];
    }

    if (topic == InfoTopic.library) {
      // null — הרשימה השמורה פגומה; אין מה להציג מלבד שורת הספירה.
      final attached = data['attachedLibraries'] as List?;
      if (attached == null) return const [];
      if (attached.isEmpty) {
        return const [
          gap,
          DetailsCard(
            children: [
              DetailsInfoSection(
                title: 'מסדים אישיים',
                value: 'לא צורפו מסדי ספרים אישיים',
              ),
            ],
          ),
        ];
      }
      return [
        gap,
        const _ListHeading('מסדי ספרים אישיים'),
        for (final library in attached.whereType<Map>())
          _AttachedLibraryTile(library: library),
      ];
    }

    if (topic == InfoTopic.plugins) {
      final plugins = (data['installed'] as List?) ?? const [];
      if (plugins.isEmpty) return const [];
      return [
        gap,
        DetailsCard(
          title: 'התוספים המותקנים',
          icon: FluentIcons.puzzle_piece_24_regular,
          children: [
            for (final plugin in plugins.whereType<Map>())
              _PluginRow(plugin: plugin),
          ],
        ),
      ];
    }

    if (topic == InfoTopic.errors) {
      final recent = (data['recent'] as List?) ?? const [];
      if (recent.isEmpty) {
        return const [
          gap,
          DetailsCard(
            children: [
              DetailsInfoSection(title: 'רשומות אחרונות', value: 'אין שגיאות'),
            ],
          ),
        ];
      }
      return [
        gap,
        const _ListHeading('רשומות אחרונות'),
        for (final entry in recent.whereType<Map>()) _ErrorTile(entry: entry),
      ];
    }

    return const [];
  }
}

/// כותרת קטנה מעל רשימת כרטיסים.
class _ListHeading extends StatelessWidget {
  const _ListHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTokens.fontMD + 1,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// כרטיס לפריט ברשימה (תיקייה או שגיאה): רקע כרטיס, מסגרת ומרווח תחתון.
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// תיקיית ספרים אישיים בודדת: שם ונתיב, תגיות מצב וספירה, וקבצים ראשונים.
class _FolderTile extends StatefulWidget {
  const _FolderTile({required this.folder, required this.maxFileNames});

  final Map<dynamic, dynamic> folder;
  final int maxFileNames;

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  bool _expanded = false;

  Map<dynamic, dynamic> get folder => widget.folder;

  static final RegExp _separator = RegExp(r'[\\/]');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = '${folder['path']}';
    final storedName = '${folder['name'] ?? ''}'.trim();
    final name = storedName.isNotEmpty
        ? storedName
        : path
              .split(_separator)
              .lastWhere((s) => s.isNotEmpty, orElse: () => path);
    final exists = folder['exists'] != false;
    final hidden = folder['hidden'] == true;
    final files = (folder['files'] as List?)?.whereType<Map>().toList() ?? [];
    final shown = (_expanded ? files : files.take(widget.maxFileNames))
        .toList();
    // יש קבצים ברשימה שעוד לא הוצגו: "ועוד" פותח אותם. מעבר לרשימה (`files=`
    // קיצץ אותה) אין מה להרחיב, וזה נשאר טקסט.
    final canExpand = files.length > widget.maxFileNames;
    // ההפרש נמדד מול הספירה המלאה ולא מול אורך הרשימה: `files=` כבר קיצץ
    // אותה, ו"ועוד 0" היה מסתיר קבצים שקיימים בתיקייה. כש-`files=0` אין
    // רשימה בכלל, והספירה שבשורת התקציר כבר אומרת את מה ש"ועוד" היה אומר.
    final fileCount = folder['fileCount'];
    final remaining = (shown.isNotEmpty && fileCount is int)
        ? fileCount - shown.length
        : 0;
    final types = InfoValueFormat.folderTypes(folder);
    final scanError = folder['scanError'];

    return _ItemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                !exists
                    ? FluentIcons.folder_prohibited_24_regular
                    : hidden
                    ? FluentIcons.eye_off_24_regular
                    : FluentIcons.folder_open_24_regular,
                size: AppTokens.fontXL,
                color: exists ? cs.primary : cs.error,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: AppTokens.fontMD + 1,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _FolderPath(
                      path: path,
                      // תיקייה שלא נמצאה אין מה לפתוח.
                      onOpen: exists && _canOpenPaths
                          ? () => _openInfoPath(path)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Wrap(
            spacing: AppTokens.spaceSM - 2,
            runSpacing: AppTokens.spaceSM - 2,
            children: [
              if (!exists)
                const MetaChip(
                  error: true,
                  icon: FluentIcons.folder_prohibited_24_regular,
                  label: 'התיקייה לא נמצאה',
                )
              else
                MetaChip(
                  icon: FluentIcons.document_24_regular,
                  label:
                      '${InfoValueFormat.count(folder['fileCount'])} קבצים · '
                      // LRI/PDI: בלי הבידוד הגודל מתהפך ("MB 67.9").
                      '\u2066${InfoValueFormat.bytes(folder['sizeBytes'])}\u2069',
                ),
              if (hidden)
                const MetaChip(
                  outlined: true,
                  icon: FluentIcons.eye_off_24_regular,
                  label: 'מוסתרת',
                ),
              if (folder['scanTruncated'] == true)
                const MetaChip(
                  outlined: true,
                  icon: FluentIcons.warning_24_regular,
                  label: 'סריקה חלקית',
                ),
              if (types.isNotEmpty)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: MetaChip(outlined: true, label: types),
                ),
            ],
          ),
          if (scanError != null) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              'שגיאת סריקה: $scanError',
              style: TextStyle(fontSize: AppTokens.fontSM, color: cs.error),
            ),
          ],
          if (shown.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppTokens.spaceXS),
            for (final file in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.document_24_regular,
                      size: AppTokens.fontMD,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTokens.spaceSM),
                    Expanded(
                      child: Text(
                        '${file['name']}',
                        style: const TextStyle(fontSize: AppTokens.fontSM),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (remaining > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: 2,
                start: AppTokens.fontMD + AppTokens.spaceSM,
              ),
              child: _MoreToggle(
                label: 'ועוד ${InfoValueFormat.count(remaining)}…',
                onTap: canExpand && !_expanded
                    ? () => setState(() => _expanded = true)
                    : null,
              ),
            ),
          if (_expanded && canExpand)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: 2,
                start: AppTokens.fontMD + AppTokens.spaceSM,
              ),
              child: _MoreToggle(
                label: 'הצג פחות',
                onTap: () => setState(() => _expanded = false),
              ),
            ),
        ],
      ),
    );
  }
}

/// מסד ספרים אישי מצורף: שם ונתיב לחיץ, ותגיות מצב, ספירה וגודל.
class _AttachedLibraryTile extends StatelessWidget {
  const _AttachedLibraryTile({required this.library});

  final Map<dynamic, dynamic> library;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = '${library['path']}';
    final status = '${library['status']}';
    final ok = status == 'ok';
    final name = '${library['name'] ?? ''}'.trim();
    final sizeBytes = library['sizeBytes'];
    return _ItemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.database_24_regular,
                size: AppTokens.fontXL,
                color: ok ? cs.primary : cs.error,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '${library['slug']}' : name,
                      style: TextStyle(
                        fontSize: AppTokens.fontMD + 1,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _FolderPath(
                      path: path,
                      onOpen: _canOpenPaths ? () => _openInfoPath(path) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Wrap(
            spacing: AppTokens.spaceSM - 2,
            runSpacing: AppTokens.spaceSM - 2,
            children: [
              if (!ok)
                MetaChip(
                  error: true,
                  icon: FluentIcons.warning_24_regular,
                  label: _statusLabel(status),
                )
              else
                MetaChip(
                  icon: FluentIcons.book_24_regular,
                  label:
                      '${InfoValueFormat.count(library['bookCount'])} ספרים · '
                      '\u2066${sizeBytes == null ? InfoValueFormat.dash : InfoValueFormat.bytes(sizeBytes)}\u2069',
                ),
              if (library['hidden'] == true)
                const MetaChip(
                  outlined: true,
                  icon: FluentIcons.eye_off_24_regular,
                  label: 'מוסתר',
                ),
              MetaChip(
                outlined: true,
                icon: library['mode'] == 'copy'
                    ? FluentIcons.copy_24_regular
                    : FluentIcons.link_24_regular,
                label: library['mode'] == 'copy' ? 'עותק מנוהל' : 'קישור לקובץ',
              ),
              MetaChip(
                outlined: true,
                icon: FluentIcons.folder_24_regular,
                label: library['placement'] == 'mergeIntoLibrary'
                    ? 'ממוזג לספרייה'
                    : 'בעץ נפרד',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    'unreachable' => 'הקובץ לא נגיש',
    'invalid' => 'מסד לא תקין',
    'duplicateSlug' => 'מזהה כפול',
    _ => status,
  };
}

/// נתיב התיקייה בכרטיס: לחיץ (פותח במנהל הקבצים) כשיש [onOpen].
class _FolderPath extends StatelessWidget {
  const _FolderPath({required this.path, this.onOpen});

  final String path;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(
      path,
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontSize: AppTokens.fontSM,
        color: onOpen == null ? cs.onSurfaceVariant : cs.primary,
        decoration: onOpen == null ? null : TextDecoration.underline,
        decorationColor: cs.primary,
      ),
    );
    if (onOpen == null) return text;
    return Tooltip(
      message: 'פתיחה במנהל הקבצים',
      child: InkWell(
        onTap: onOpen,
        borderRadius: AppTokens.borderRadiusAll,
        child: text,
      ),
    );
  }
}

/// "ועוד N…" / "הצג פחות" מתחת לרשימת הקבצים: קישור כשיש מה להרחיב או לכווץ,
/// ואחרת טקסט עמום.
class _MoreToggle extends StatelessWidget {
  const _MoreToggle({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(
      label,
      style: TextStyle(
        fontSize: AppTokens.fontSM,
        color: onTap == null ? cs.onSurfaceVariant : cs.primary,
        decoration: onTap == null ? null : TextDecoration.underline,
        decorationColor: cs.primary,
      ),
    );
    if (onTap == null) return text;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusAll,
        child: text,
      ),
    );
  }
}

/// שורת תוסף מותקן: המזהה, והגרסה בתגית (מושבת מסומן בה).
class _PluginRow extends StatelessWidget {
  const _PluginRow({required this.plugin});

  final Map<dynamic, dynamic> plugin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = plugin['enabled'] != false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${plugin['id']}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: AppTokens.fontMD,
                  fontWeight: FontWeight.w600,
                  color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Directionality(
            textDirection: TextDirection.ltr,
            child: MetaChip(
              outlined: !enabled,
              label: InfoValueFormat.pluginVersion(plugin),
            ),
          ),
        ],
      ),
    );
  }
}

/// רשומת שגיאה בודדת: כותרת, זמן בתגית, והודעה מקוצרת.
class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.entry});

  final Map<dynamic, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timestamp = InfoValueFormat.dateTimeOrDash(entry['timestamp']);
    final message = '${entry['message'] ?? ''}'.trim();

    return _ItemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.error_circle_24_regular,
                size: AppTokens.fontXL,
                color: cs.error,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry['title']}',
                      style: TextStyle(
                        fontSize: AppTokens.fontMD,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceXS),
                    // התאריך מתחת לכותרת: ברוחב טלפון אין לו מקום לידה.
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: MetaChip(
                        outlined: true,
                        icon: FluentIcons.clock_24_regular,
                        label: timestamp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSM),
              child: Text(
                message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTokens.fontSM,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
