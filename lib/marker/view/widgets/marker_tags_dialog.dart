import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/view/widgets/marker_dialogs.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// שינוי שם, מיזוג ומחיקה של תגיות בכל הסימונים. שם קיים ממזג את שתי
/// התגיות לאחת.
Future<void> showMarkerTagsDialog(BuildContext context) async {
  final tags = await MarkerActions.instance.tags();
  if (!context.mounted) return;
  await showSingleActionDialog(
    context: context,
    title: 'ניהול תגיות',
    confirmText: 'סגירה',
    customContent: SizedBox(
      width: 420,
      child: _TagsList(initial: tags),
    ),
  );
}

class _TagsList extends StatefulWidget {
  final List<({String tag, int count})> initial;

  const _TagsList({required this.initial});

  @override
  State<_TagsList> createState() => _TagsListState();
}

class _TagsListState extends State<_TagsList> {
  late List<({String tag, int count})> _tags = widget.initial;

  Future<void> _replace(String from, String? to) async {
    try {
      final changed = await MarkerActions.instance.replaceTag(from, to);
      UiSnack.showQuick(MarkerMessages.tagReplaced(changed));
      final tags = await MarkerActions.instance.tags();
      if (mounted) setState(() => _tags = tags);
    } catch (error) {
      debugPrint('Marker tag change failed: $error');
      UiSnack.showError(MarkerMessages.saveFailed);
    }
  }

  Future<void> _rename(String tag) async {
    final controller = TextEditingController(text: tag);
    try {
      final confirmed = await showTwoActionsDialog(
        context: context,
        title: 'שינוי שם תגית',
        content: '',
        confirmText: 'שמירה',
        customContent: RtlTextField(
          controller: controller,
          autofocus: true,
          inputFormatters: [
            LengthLimitingTextInputFormatter(MarkerHighlight.maxTagLength),
          ],
          decoration: const InputDecoration(
            helperText: 'שם של תגית קיימת ימזג את שתיהן',
          ),
        ),
      );
      final name = MarkerHighlight.normalizeTags([controller.text]);
      if (confirmed == true && name.isNotEmpty && name.single != tag) {
        await _replace(tag, name.single);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _delete(String tag, int count) async {
    final confirmed = await confirmMarkerAction(
      context,
      title: 'מחיקת תגית',
      content: count == 1
          ? 'להסיר את התגית "$tag" מהסימון? הסימון עצמו יישאר.'
          : 'להסיר את התגית "$tag" מ-$count סימונים? הסימונים עצמם יישארו.',
      confirmText: 'הסרה',
    );
    if (confirmed) await _replace(tag, null);
  }

  @override
  Widget build(BuildContext context) {
    if (_tags.isEmpty) return const Text('אין עדיין תגיות.');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final tag in _tags)
            ListTile(
              hoverColor: Colors.transparent,
              title: Text(tag.tag),
              subtitle: Text(
                tag.count == 1 ? 'סימון אחד' : '${tag.count} סימונים',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'שינוי שם',
                    onPressed: () => _rename(tag.tag),
                    icon: const Icon(FluentIcons.edit_24_regular),
                  ),
                  IconButton(
                    tooltip: 'מחיקה',
                    onPressed: () => _delete(tag.tag, tag.count),
                    icon: const Icon(FluentIcons.delete_24_regular),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
