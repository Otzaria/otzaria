import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNoteContentView extends StatelessWidget {
  final PersonalNote note;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final bool allowSelection;
  final void Function(String url)? onLinkTap;

  const PersonalNoteContentView({
    super.key,
    required this.note,
    this.textStyle,
    this.textAlign = TextAlign.justify,
    this.allowSelection = true,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final links = _extractLinks();
    if (note.contentFormat == PersonalNoteContentFormat.quillDelta) {
      final controller = quill.QuillController(
        document: _buildDocument(note.content),
        selection: const TextSelection.collapsed(offset: 0),
      );
      controller.readOnly = true;

      final editor = quill.QuillEditor(
        controller: controller,
        focusNode: FocusNode(),
        scrollController: ScrollController(),
        config: const quill.QuillEditorConfig(
          autoFocus: false,
          expands: false,
          padding: EdgeInsets.zero,
          showCursor: false,
          scrollable: false,
        ),
      );

      return Directionality(
        textDirection: TextDirection.rtl,
        child: DefaultTextStyle(
          style: textStyle ?? Theme.of(context).textTheme.bodyMedium!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              editor,
              if (links.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildLinks(context, links),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          note.contentPlain,
          style: textStyle,
          textAlign: textAlign,
          textDirection: TextDirection.rtl,
        ),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildLinks(context, links),
        ],
      ],
    );
  }

  quill.Document _buildDocument(String content) {
    try {
      final decoded = jsonDecode(content) as List<dynamic>;
      return quill.Document.fromJson(decoded);
    } catch (_) {
      return quill.Document()..insert(0, content);
    }
  }

  List<({String label, String url})> _extractLinks() {
    if (note.contentFormat != PersonalNoteContentFormat.quillDelta) {
      return const [];
    }

    try {
      final decoded = jsonDecode(note.content) as List<dynamic>;
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
    } catch (_) {
      return const [];
    }
  }

  Widget _buildLinks(BuildContext context, List<({String label, String url})> links) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: links.map((link) {
        final label = link.label.isNotEmpty ? link.label : link.url;
        return ActionChip(
          label: Text(label, overflow: TextOverflow.ellipsis),
          onPressed: onLinkTap == null ? null : () => onLinkTap!(link.url),
        );
      }).toList(),
    );
  }
}
