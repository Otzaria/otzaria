import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_link_detection.dart';
import 'package:otzaria/personal_notes/widgets/note_delta_preview.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// מציג את ההערות של שורה בחלון קריאה ממורכז.
Future<bool?> showPersonalNotesDialog({
  required BuildContext context,
  required List<PersonalNote> notes,
}) => showSingleActionDialog(
  context: context,
  title: notes.length == 1 ? 'הערה אישית' : 'הערות אישיות',
  icon: FluentIcons.note_24_regular,
  headerBand: true,
  customContent: PersonalNotesListView(notes: notes),
  confirmText: 'סגור',
);

/// מציגה תוכן הערה, עם משאבי Quill רק כשנדרשת אינטראקציה או עיצוב מורכב.
class PersonalNoteContentView extends StatefulWidget {
  final PersonalNote note;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final void Function(String url)? onLinkTap;

  /// כשמוגדר, מקצר את התוכן ל-N התווים הראשונים. נועד לתצוגות מקדימות
  /// (כרטיסי רשת) כדי לא לרנדר הערות ארוכות מאוד במלואן — QuillEditor
  /// במצב לא-נגלל מחשב layout לכל הטקסט, כך שהקיצור הוא שמונע jank.
  final int? maxPreviewChars;

  /// כש-false משתמש ברינדור קל לעיצובים נתמכים, וב-Quill לשאר העיצובים.
  /// גוף התצוגה המקדימה אינו מקבל קלט.
  final bool interactive;

  const PersonalNoteContentView({
    super.key,
    required this.note,
    this.textStyle,
    this.textAlign = TextAlign.justify,
    this.onLinkTap,
    this.maxPreviewChars,
    this.interactive = true,
  });

  @override
  State<PersonalNoteContentView> createState() =>
      _PersonalNoteContentViewState();
}

class _PersonalNoteContentViewState extends State<PersonalNoteContentView> {
  final _editorKey = GlobalKey();
  quill.QuillController? _controller;
  quill.Document? _previewDocument;
  FocusNode? _focusNode;
  ScrollController? _scrollController;
  List<({String label, String url})> _links = const [];

  AppSelectionAreaState? _host;

  @override
  void initState() {
    super.initState();
    _buildContent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.interactive) return;
    final host = AppSelectionArea.maybeOf(context);
    if (host == _host) return;
    _host?.removeSelectionSource(_selectedText);
    _host = host
      ?..addSelectionSource(
        _selectedText,
        containsPosition: _selectionSourceContainsPosition,
      );
  }

  String _selectedText() => _controller?.getPlainText() ?? '';

  bool _selectionSourceContainsPosition(Offset position) {
    final renderObject = _editorKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    return (Offset.zero & renderObject.size).contains(
      renderObject.globalToLocal(position),
    );
  }

  @override
  void didUpdateWidget(PersonalNoteContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.content != widget.note.content ||
        oldWidget.note.contentFormat != widget.note.contentFormat ||
        oldWidget.maxPreviewChars != widget.maxPreviewChars ||
        oldWidget.interactive != widget.interactive) {
      _disposeControllers();
      _buildContent();
    }
  }

  @override
  void dispose() {
    _host?.removeSelectionSource(_selectedText);
    _disposeControllers();
    super.dispose();
  }

  /// מפרסר את תוכן ההערה פעם אחת ובונה את ה-controllers (אם זה Quill Delta).
  /// ה-jsonDecode נעשה פעם אחת ומשמש גם לבניית המסמך וגם לחילוץ הקישורים.
  void _buildContent() {
    final note = widget.note;
    if (note.contentFormat != PersonalNoteContentFormat.quillDelta) {
      _links = const [];
      return;
    }

    List<dynamic>? decoded;
    try {
      decoded = jsonDecode(note.content) as List<dynamic>;
    } catch (_) {
      decoded = null;
    }

    final truncated = decoded != null && widget.maxPreviewChars != null
        ? _truncateDelta(decoded, widget.maxPreviewChars!)
        : decoded;
    // כתובות שהודבקו כטקסט רגיל הופכות לקישורים לחיצים (גם בהערות ישנות).
    final effectiveDelta = truncated != null
        ? linkifyDeltaOps(truncated)
        : null;

    final document = effectiveDelta != null
        ? quill.Document.fromJson(effectiveDelta)
        : (quill.Document()..insert(0, note.content));

    if (widget.interactive || !NoteDeltaPreview.supports(document)) {
      _controller = quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      )..readOnly = true;
      _focusNode = FocusNode();
      _scrollController = ScrollController();
    } else {
      _previewDocument = document;
    }
    // חילוץ הקישורים מה-Delta האפקטיבי (המקוצר בתצוגה מקדימה, המלא אחרת)
    // כדי שלא נבנה chips לקישורים שכלל לא מוצגים בתצוגה המקוצרת.
    _links = effectiveDelta != null ? _extractLinks(effectiveDelta) : const [];
  }

  void _disposeControllers() {
    _controller?.dispose();
    _focusNode?.dispose();
    _scrollController?.dispose();
    _controller = null;
    _previewDocument = null;
    _focusNode = null;
    _scrollController = null;
  }

  @override
  Widget build(BuildContext context) {
    final previewDocument = _previewDocument;
    if (previewDocument != null) {
      return _withLinks(context, NoteDeltaPreview(document: previewDocument));
    }
    final controller = _controller;
    if (controller != null) {
      // בתוך AppSelectionArea תפריט ההעתקה מגיע ממנו; שני אזורי תפריט מקוננים
      // היו פותחים שני תפריטים.
      final hostHasOwnMenu = _host != null;
      // במגע נשאר התפריט הטבעי של העורך, כמו ב-AppSelectionArea.
      final platform = Theme.of(context).platform;
      final useNativeTouchMenu =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      final useOwnMenu =
          widget.interactive && !hostHasOwnMenu && !useNativeTouchMenu;
      Widget editor = quill.QuillEditor(
        key: _editorKey,
        controller: controller,
        focusNode: _focusNode!,
        scrollController: _scrollController!,
        config: quill.QuillEditorConfig(
          contextMenuBuilder: hostHasOwnMenu || useOwnMenu
              ? (context, _) => const SizedBox.shrink()
              : null,
          autoFocus: false,
          expands: false,
          padding: EdgeInsets.zero,
          showCursor: false,
          enableInteractiveSelection: widget.interactive,
          scrollable: false,
          // בלי הרישום, Quill מוסיף https:// לפני otzaria:// בעת לחיצה.
          customLinkPrefixes: const ['otzaria://', 'zayit://'],
          onLaunchUrl: widget.onLinkTap,
        ),
      );

      if (useOwnMenu) {
        editor = AppContextMenuRegion(
          menuBuilder: (_, _) {
            final selected = controller.getPlainText();
            return [
              AppContextMenuEntry(
                label: 'העתק',
                icon: FluentIcons.copy_24_regular,
                enabled: selected.trim().isNotEmpty,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: selected));
                  UiSnack.show(CommonMessages.textCopiedShort);
                },
              ),
            ];
          },
          child: editor,
        );
      }

      if (!widget.interactive) {
        editor = ExcludeFocus(child: IgnorePointer(child: editor));
      }
      return _withLinks(context, editor);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _previewPlain,
          style: widget.textStyle,
          textAlign: widget.textAlign,
        ),
        if (_links.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildLinks(context, _links),
        ],
      ],
    );
  }

  Widget _withLinks(BuildContext context, Widget body) {
    return DefaultTextStyle(
      style: widget.textStyle ?? Theme.of(context).textTheme.bodyMedium!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (_links.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildLinks(context, _links),
          ],
        ],
      ),
    );
  }

  List<({String label, String url})> _extractLinks(List<dynamic> decoded) {
    final links = <({String label, String url})>[];
    for (final op in decoded) {
      if (op is! Map<String, dynamic>) continue;
      final attributes = op['attributes'];
      final insert = op['insert'];
      if (attributes is Map<String, dynamic> &&
          attributes['link'] is String &&
          insert is String) {
        links.add((label: insert.trim(), url: attributes['link'] as String));
      }
    }
    return links;
  }

  Widget _buildLinks(
    BuildContext context,
    List<({String label, String url})> links,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: links.map((link) {
        final label = link.label.isNotEmpty ? link.label : link.url;
        return ActionChip(
          // מגבילים את רוחב התווית כדי ש-ellipsis יחתוך קישורים ארוכים
          // (Wrap נותן רוחב בלתי-מוגבל לילדיו, ובלי מגבלה ellipsis לא פועל).
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          onPressed: widget.onLinkTap == null
              ? null
              : () => widget.onLinkTap!(link.url),
        );
      }).toList(),
    );
  }

  /// גרסת טקסט פשוט מקוצרת לתצוגה מקדימה (כש-[maxPreviewChars] מוגדר).
  String get _previewPlain {
    final text = widget.note.contentPlain;
    final max = widget.maxPreviewChars;
    if (max != null && text.length > max) {
      return '${text.substring(0, max)}…';
    }
    return text;
  }

  /// מקצר Delta ל-[maxChars] התווים הראשונים, תוך שמירה על מבנה תקין
  /// (סיום בתו שורה כפי ש-Quill דורש). אובייקטים מוטמעים מדולגים בתצוגה
  /// מקדימה. ה-attributes של כל קטע נשמרים כך שהעיצוב נותר.
  List<dynamic> _truncateDelta(List<dynamic> decoded, int maxChars) {
    final result = <Map<String, dynamic>>[];
    var count = 0;
    var truncated = false;

    for (final op in decoded) {
      if (op is! Map<String, dynamic>) continue;
      final insert = op['insert'];
      if (insert is! String) continue; // embed — מדלגים בתצוגה מקדימה
      final remaining = maxChars - count;
      if (insert.length <= remaining) {
        result.add(op);
        count += insert.length;
      } else {
        if (remaining > 0) {
          result.add({...op, 'insert': insert.substring(0, remaining)});
        }
        truncated = true;
        break;
      }
    }

    // Document תקין חייב להסתיים בתו שורה.
    final last = result.isEmpty ? null : result.last['insert'] as String?;
    if (last == null || !last.endsWith('\n')) {
      result.add({'insert': truncated ? '…\n' : '\n'});
    }
    return result;
  }
}

/// מציגה את כל ההערות האישיות של שורה אחת, זו אחר זו עם מפריד ביניהן.
///
/// משמשת את הסימן שבצד השורה: כשיש יותר מהערה אחת באותה שורה, לחיצה ארוכה
/// על הסימן פותחת דיאלוג עם כל ההערות (ולא רק האחרונה). התוכן נגלל אם הוא
/// חורג מ-[maxHeight] כדי שדיאלוג עם הערות רבות לא יחרוג מהמסך.
class PersonalNotesListView extends StatelessWidget {
  final List<PersonalNote> notes;
  final double maxHeight;
  final void Function(String url)? onLinkTap;

  const PersonalNotesListView({
    super.key,
    required this.notes,
    this.maxHeight = 400,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < notes.length; i++) ...[
              if (i > 0) const Divider(height: 24),
              PersonalNoteContentView(note: notes[i], onLinkTap: onLinkTap),
            ],
          ],
        ),
      ),
    );
  }
}
