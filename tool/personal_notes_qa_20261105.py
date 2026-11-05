#!/usr/bin/env python3
"""Validate the exact personal-notes candidate without modifying its Git commit."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

EXPECTED_HASHES = {'lib/personal_notes/bloc/personal_notes_bloc.dart': 'e5a7c2203773e4fcc4d9b9e396aea4852d4eb723858634ac1ae659d58812e24c', 'lib/personal_notes/bloc/personal_notes_state.dart': '52ec9828c246c5faf7992cc10a84af7ddf9ff95160afb34526cd90193a7566a0', 'lib/personal_notes/services/personal_notes_import_export_service.dart': 'b5b460e2f2976a5ac88c1101eed8db47357233095ce7c55ae0609f6ab4c0188e', 'lib/personal_notes/storage/personal_notes_database.dart': '60a8e6fc62e16793eefd27bfb6a76ab3e16752f523a66aadb9a9073a97e5aad4', 'lib/personal_notes/utils/note_collection_utils.dart': '3e0567b3a90f18315615a02adb505c0bd63b5cb70299ff3e46994e1079b80ebf', 'lib/personal_notes/view/personal_notes_screen.dart': '8a1083001541587ce4a5400a1895094fa24166970e38808815b468617ce9949f', 'lib/personal_notes/widgets/note_delta_preview.dart': '3fa69497f48cf258445337ea282c30dd5f7ce797f31a243347d596c2a1524886', 'lib/personal_notes/widgets/note_tile.dart': '08128e32ce670de83e2942293bd91feb9e91a868a092829b2a06ba0f17ec4952', 'lib/personal_notes/widgets/personal_note_content_view.dart': '44bfa695068479d2c737c09c4d37689a88a57addb66db2f958e42ad59015ce0e', 'lib/personal_notes/widgets/personal_note_editor.dart': 'f453dbdc3757f44823220c809b8b606db024a637dea75d4e5c9d475ac5154887', 'lib/personal_notes/widgets/personal_note_styles.dart': '52372fab5c7b6c1d6fec8e16b1a2252dfe7bd9613355df0fc9330e99231ba915', 'lib/personal_notes/widgets/personal_notes_sidebar.dart': '368162d7d4117910029427921dbf0e719783a54cd6699253d79e51c6d499e58f', 'lib/text_book/utils/note_inline_render.dart': 'e926c0cc5b98d8eed9514b8b46e794c4c22e70b5a8e7f4910bcd6c9bc8ac41c1', 'lib/text_book/view/combined_view/combined_book_screen.dart': '7dd5b4a3dc20258c395643a15271e2bb9b19717868009f06f0faaa5aee0efdc8', 'lib/text_book/view/page_shape/page_shape_screen.dart': 'a4bf23a367597715dca986f7e1392c9d5fa7eeb1427f51ee710ae0d4b158c502', 'lib/text_book/view/page_shape/simple_text_viewer.dart': '69e8cbcb8112e69bcc7829c3da360c40946c5039c4efdf81d06b2e72a401e848', 'lib/text_book/view/splited_view/splited_view_screen.dart': 'f3aa7a5b082f0a55658680e9377185e1b9ba932cdcce96eeb87cc9ec19664491', 'test/personal_notes/bloc/personal_notes_visible_filter_test.dart': 'd412341f2f67e3e1e105c41d3837a9cdf08ba65dbea3b174ccdfa77f2860aaf9', 'test/personal_notes/imported_delta_preview_test.dart': '6ce265e657469465b2d35df7c44aa84d17f47706ee6515711d5c8eb1797ca898', 'test/personal_notes/note_delta_preview_test.dart': '0a1031efcc32813c2aa5bfa5dbea55021cc5c9c08f78e4698ab087962c4a58a2', 'test/personal_notes/personal_note_content_view_context_menu_test.dart': 'f2470b2fc6bb93d4f143a21c56b7bc9268e2a6cf29e83314ac9336a3070183e7', 'test/personal_notes/personal_notes_word_export_screen_test.dart': '0bfd6f7e58a165d46e69c718b7ad43fcbcf8b90cfaa1969a180d356e78ab7908', 'test/personal_notes/personal_notes_word_export_test.dart': '4d79dee9bb2ae8a729ab2895d89f95a150d47ee4faef7f1136757b751457a787', 'test/personal_notes/storage/personal_notes_database_test.dart': '4ddcd0026b61f29aa174d7328042414584e09ddb6279b19957f0d7dea4b0922f', 'test/personal_notes/widgets/personal_notes_sidebar_reveal_test.dart': '84364ebae1b1f656ef2040c9e97bce4597a50480859b8c955f1cedfa76b62b68', 'test/text_book/utils/note_inline_render_test.dart': '1fd5f283980542803e774cd659f75117fec19a576fea9159116d0cd42bc003cd', 'test/text_book/view/combined_view/combined_book_screen_test.dart': 'd44d37bb86f924c03e69f2203e20d2b2f2713b2a3f7451413be21cbdc6e30ea5', 'test/text_book/view/page_shape/page_shape_screen_settings_test.dart': '713131461e8f68d26f2df44ed3a0bd6ff218efc72b5129ba973be8effeeb5a0d', 'test/text_book/view/page_shape/simple_text_viewer_test.dart': 'a2c0236f512df24fc4afbb48a1340f77cf5f96b3903f4f2111141e7b405e04a0', 'test/text_book/view/splited_view_toggle_commentators_pane_test.dart': '4b59a460900b378b620b4575454ca35be3ec89591868dd61a256d3d63f43a59e'}
CAPTURE_SOURCES = json.loads('{"personal_notes_ui_capture_test.dart": "import \'dart:convert\';\\nimport \'dart:io\';\\nimport \'dart:ui\' as ui;\\n\\nimport \'package:flutter/material.dart\';\\nimport \'package:flutter/rendering.dart\';\\nimport \'package:flutter/services.dart\';\\nimport \'package:flutter_test/flutter_test.dart\';\\nimport \'package:otzaria/personal_notes/models/personal_note.dart\';\\nimport \'package:otzaria/personal_notes/widgets/note_tile.dart\' as after_tile;\\nimport \'package:otzaria/personal_notes/widgets/personal_note_editor.dart\'\\n    as after_editor;\\nimport \'package:otzaria/settings/engine/app_settings_store.dart\';\\nimport \'package:otzaria/theme/app_seed_colors.dart\';\\nimport \'package:otzaria/theme/app_surfaces.dart\';\\nimport \'package:otzaria/theme/app_theme_data.dart\';\\n\\nimport \'__MEMORY_CACHE_HELPER_URI__\';\\nimport \'before_note_tile.dart\' as before_tile;\\nimport \'before_personal_note_editor.dart\' as before_editor;\\n\\nconst _text =\\n    \'שורה ראשונה: בירור בלשון המשנה.\\\\n\'\\n    \'שורה שנייה: הקשר בין שני הפירושים.\\\\n\'\\n    \'שורה שלישית: הערה נוספת על הדברים.\\\\n\'\\n    \'שורה רביעית: מקום להרחבה ולעיון.\\\\n\';\\n\\nvoid main() {\\n  TestWidgetsFlutterBinding.ensureInitialized();\\n\\n  setUpAll(() async {\\n    await Settings.init(cacheProvider: MemoryCacheProvider());\\n    final manifest = jsonDecode(\\n      await rootBundle.loadString(\'FontManifest.json\'),\\n    ) as List<dynamic>;\\n    for (final entry in manifest.cast<Map<String, dynamic>>()) {\\n      final family = entry[\'family\'] as String;\\n      if (family != \'Rubik\' &&\\n          !family.toLowerCase().contains(\'fluent\') &&\\n          !family.toLowerCase().contains(\'otzaria\'))\\n        continue;\\n      final loader = FontLoader(family);\\n      for (final asset\\n          in (entry[\'fonts\'] as List<dynamic>).cast<Map<String, dynamic>>()) {\\n        loader.addFont(rootBundle.load(asset[\'asset\'] as String));\\n      }\\n      await loader.load();\\n    }\\n  });\\n\\n  for (final brightness in Brightness.values) {\\n    for (final before in [true, false]) {\\n      final label = \'${before ? \'before\' : \'after\'}-${brightness.name}\';\\n      testWidgets(\'צילום רכיבי הערות $label\', (tester) async {\\n        tester.view.physicalSize = const Size(660, 820);\\n        tester.view.devicePixelRatio = 1;\\n        addTearDown(tester.view.reset);\\n        final oldController = before_editor.buildPersonalNoteEditorController(\\n          initialContent: _text,\\n          initialFormat: PersonalNoteContentFormat.plain,\\n        );\\n        final newController = after_editor.buildPersonalNoteEditorController(\\n          initialContent: _text,\\n          initialFormat: PersonalNoteContentFormat.plain,\\n        );\\n        final focus = FocusNode();\\n        final scroll = ScrollController();\\n        final boundaryKey = GlobalKey();\\n        final colorScheme = AppThemeData.createColorScheme(\\n          brightness == Brightness.light\\n              ? AppSeedColors.defaultLight\\n              : AppSeedColors.defaultDark,\\n          brightness,\\n        );\\n        final baseTheme = brightness == Brightness.light\\n            ? AppThemeData.light(colorScheme, compactMenuMode: false)\\n            : AppThemeData.dark(colorScheme, compactMenuMode: false);\\n        final theme = baseTheme.copyWith(\\n          textTheme: baseTheme.textTheme.apply(fontFamily: \'Rubik\'),\\n        );\\n        final note = PersonalNote(\\n          id: \'capture\',\\n          bookId: \'ספר בדיקה\',\\n          lineNumber: 1,\\n          displayTitle: \'משנה א — בירור הלשון\',\\n          lastKnownLineNumber: 1,\\n          status: PersonalNoteStatus.located,\\n          content: \'פירוש קצר על לשון המשנה.\\\\nאפשר להוסיף כאן הערה נוספת.\',\\n          contentPlain: \'פירוש קצר על לשון המשנה.\\\\nאפשר להוסיף כאן הערה נוספת.\',\\n          contentFormat: PersonalNoteContentFormat.plain,\\n          createdAt: DateTime(2026),\\n          updatedAt: DateTime(2026),\\n        );\\n        await tester.pumpWidget(\\n          MaterialApp(\\n            theme: theme,\\n            home: Directionality(\\n              textDirection: TextDirection.rtl,\\n              child: Scaffold(\\n                body: RepaintBoundary(\\n                  key: boundaryKey,\\n                  child: Builder(\\n                    builder: (context) => ColoredBox(\\n                      color: AppSurfaces.navPanelBackground(context),\\n                      child: SizedBox.expand(\\n                        child: Padding(\\n                          padding: const EdgeInsets.all(24),\\n                          child: Column(\\n                            crossAxisAlignment: CrossAxisAlignment.stretch,\\n                            children: [\\n                              Text(\\n                                before\\n                                    ? \'לפני התיקון — dev f4085b9\'\\n                                    : \'אחרי התיקון\',\\n                                style: theme.textTheme.headlineSmall,\\n                              ),\\n                              const SizedBox(height: 20),\\n                              Text(\\n                                \'חלונית הערות אישיות\',\\n                                style: theme.textTheme.titleMedium,\\n                              ),\\n                              const SizedBox(height: 12),\\n                              before\\n                                  ? before_tile.NoteTile(\\n                                      note: note,\\n                                      onTap: () {},\\n                                      onSave: (_) {},\\n                                      onDelete: () {},\\n                                      onLinkTap: (_) {},\\n                                      linkableNotes: const [],\\n                                      defaultExpanded: true,\\n                                      bookId: note.bookId,\\n                                    )\\n                                  : after_tile.NoteTile(\\n                                      note: note,\\n                                      onTap: () {},\\n                                      onSave: (_) {},\\n                                      onDelete: () {},\\n                                      onLinkTap: (_) {},\\n                                      linkableNotes: const [],\\n                                      defaultExpanded: true,\\n                                      bookId: note.bookId,\\n                                    ),\\n                              const SizedBox(height: 32),\\n                              Text(\\n                                \'ריווח השורות בעורך ההערות\',\\n                                style: theme.textTheme.titleMedium,\\n                              ),\\n                              const SizedBox(height: 12),\\n                              before\\n                                  ? before_editor.PersonalNoteEditorBody(\\n                                      controller: oldController,\\n                                      focusNode: focus,\\n                                      scrollController: scroll,\\n                                      autofocus: false,\\n                                      linkableNotes: const [],\\n                                    )\\n                                  : after_editor.PersonalNoteEditorBody(\\n                                      controller: newController,\\n                                      focusNode: focus,\\n                                      scrollController: scroll,\\n                                      autofocus: false,\\n                                      linkableNotes: const [],\\n                                    ),\\n                            ],\\n                          ),\\n                        ),\\n                      ),\\n                    ),\\n                  ),\\n                ),\\n              ),\\n            ),\\n          ),\\n        );\\n        await tester.pumpAndSettle();\\n        expect(tester.takeException(), isNull);\\n        await tester.runAsync(() async {\\n          final boundary =\\n              boundaryKey.currentContext!.findRenderObject()!\\n                  as RenderRepaintBoundary;\\n          final image = await boundary.toImage(pixelRatio: 2);\\n          final bytes = (await image.toByteData(\\n            format: ui.ImageByteFormat.png,\\n          ))!;\\n          await File(\'__CAPTURE_OUTPUT_DIR__/$label.png\')\\n              .writeAsBytes(bytes.buffer.asUint8List());\\n          image.dispose();\\n        });\\n        await tester.pumpWidget(const SizedBox());\\n        oldController.quillController.dispose();\\n        newController.quillController.dispose();\\n        focus.dispose();\\n        scroll.dispose();\\n      });\\n    }\\n  }\\n}\\n", "before_note_tile.dart": "import \'package:flutter/material.dart\';\\nimport \'package:fluentui_system_icons/fluentui_system_icons.dart\';\\n\\nimport \'package:otzaria/personal_notes/models/personal_note.dart\';\\nimport \'package:otzaria/personal_notes/services/personal_note_draft_service.dart\';\\nimport \'package:otzaria/personal_notes/widgets/personal_note_content_view.dart\';\\nimport \'package:otzaria/personal_notes/widgets/personal_note_editor.dart\';\\nimport \'package:otzaria/personal_notes/widgets/inline_note_editor.dart\';\\n\\nclass NoteTile extends StatefulWidget {\\n  final PersonalNote note;\\n  final VoidCallback? onTap;\\n  final ValueChanged<PersonalNoteEditorResult> onSave;\\n  final VoidCallback onDelete;\\n  final ValueChanged<String> onLinkTap;\\n  final bool defaultExpanded;\\n  final String bookId;\\n  final int? categoryId;\\n  final List<PersonalNote> linkableNotes;\\n  final Widget? extraAction;\\n  final Color? backgroundColor;\\n  final Widget? subtitle;\\n\\n  /// טוקן בקשת הרחבה. כשמשתנה לערך לא-null (לחיצה על סימון inline של שורה זו)\\n  /// ההערה נפתחת גם אם [defaultExpanded] הוא false.\\n  final int? expandToken;\\n\\n  const NoteTile({\\n    super.key,\\n    required this.note,\\n    this.onTap,\\n    required this.onSave,\\n    required this.onDelete,\\n    required this.onLinkTap,\\n    required this.defaultExpanded,\\n    required this.bookId,\\n    this.categoryId,\\n    required this.linkableNotes,\\n    this.extraAction,\\n    this.backgroundColor,\\n    this.subtitle,\\n    this.expandToken,\\n  });\\n\\n  @override\\n  State<NoteTile> createState() => _NoteTileState();\\n}\\n\\nclass _NoteTileState extends State<NoteTile> {\\n  late bool _isExpanded;\\n  bool _isInlineEditing = false;\\n  String? _draftContent;\\n  PersonalNoteContentFormat? _draftFormat;\\n  final PersonalNoteDraftService _draftService = PersonalNoteDraftService();\\n  final ValueNotifier<int> _cancelRequest = ValueNotifier(0);\\n\\n  @override\\n  void initState() {\\n    super.initState();\\n    // נפתח לפי ברירת המחדל, או בכפייה אם הגענו דרך לחיצה על סימון inline.\\n    _isExpanded = widget.defaultExpanded || widget.expandToken != null;\\n    _restoreDraftIfExists();\\n  }\\n\\n  @override\\n  void didUpdateWidget(covariant NoteTile oldWidget) {\\n    super.didUpdateWidget(oldWidget);\\n    // בקשת הרחבה חדשה (לחיצה על סימון inline) — פותחים את ההערה.\\n    if (widget.expandToken != null &&\\n        widget.expandToken != oldWidget.expandToken &&\\n        !_isExpanded) {\\n      setState(() => _isExpanded = true);\\n    }\\n    if (oldWidget.note.id != widget.note.id ||\\n        oldWidget.bookId != widget.bookId ||\\n        oldWidget.note.updatedAt != widget.note.updatedAt) {\\n      _draftContent = null;\\n      _draftFormat = null;\\n      _restoreDraftIfExists();\\n    }\\n  }\\n\\n  Future<void> _restoreDraftIfExists() async {\\n    final draft = await _draftService.loadDraft(\\n      bookId: widget.bookId,\\n      categoryId: widget.categoryId,\\n      noteId: widget.note.id,\\n    );\\n    if (!mounted || draft == null) {\\n      return;\\n    }\\n\\n    setState(() {\\n      _draftContent = draft.content;\\n      _draftFormat = draft.contentFormat;\\n      _isExpanded = true;\\n      _isInlineEditing = true;\\n    });\\n  }\\n\\n  void _startInlineEdit() {\\n    setState(() {\\n      _isExpanded = true;\\n      _isInlineEditing = true;\\n    });\\n  }\\n\\n  void _cancelInlineEdit() {\\n    setState(() {\\n      _isInlineEditing = false;\\n    });\\n  }\\n\\n  void _requestInlineEditCancellation() {\\n    _cancelRequest.value++;\\n  }\\n\\n  void _handleSave(PersonalNoteEditorResult result) {\\n    widget.onSave(result);\\n    _cancelInlineEdit();\\n  }\\n\\n  @override\\n  Widget build(BuildContext context) {\\n    if (_isInlineEditing) {\\n      final titleText =\\n          widget.note.displayTitle != null &&\\n              widget.note.displayTitle!.isNotEmpty\\n          ? \'עריכת הערה - ${widget.note.displayTitle}\'\\n          : (widget.note.lineNumber != null\\n                ? \'עריכת הערה - שורה ${widget.note.lineNumber}\'\\n                : \'עריכת הערה\');\\n\\n      return InlineNoteEditorCard(\\n        icon: FluentIcons.note_edit_24_regular,\\n        title: titleText,\\n        onCancelPressed: _requestInlineEditCancellation,\\n        editor: InlineNoteEditor(\\n          note: widget.note,\\n          referenceText: widget.note.displayTitle,\\n          bookId: widget.bookId,\\n          categoryId: widget.categoryId,\\n          initialContent: _draftContent ?? widget.note.content,\\n          initialFormat: _draftFormat ?? widget.note.contentFormat,\\n          draftNoteId: widget.note.id,\\n          linkableNotes: widget.linkableNotes,\\n          onSave: _handleSave,\\n          onCancel: _cancelInlineEdit,\\n          cancelRequest: _cancelRequest,\\n        ),\\n      );\\n    }\\n\\n    final bgColor =\\n        widget.backgroundColor ?? Theme.of(context).colorScheme.surface;\\n\\n    return Column(\\n      children: [\\n        InkWell(\\n          onTap: widget.onTap,\\n          child: Container(\\n            padding: const EdgeInsets.symmetric(\\n              horizontal: 16.0,\\n              vertical: 12.0,\\n            ),\\n            color: bgColor,\\n            child: Row(\\n              children: [\\n                Expanded(\\n                  child: Column(\\n                    crossAxisAlignment: CrossAxisAlignment.start,\\n                    children: [\\n                      Text(\\n                        widget.note.title,\\n                        style: Theme.of(context).textTheme.titleSmall?.copyWith(\\n                          fontWeight: FontWeight.w600,\\n                        ),\\n                        maxLines: 2,\\n                        overflow: TextOverflow.ellipsis,\\n                      ),\\n                      if (widget.subtitle != null) ...[\\n                        const SizedBox(height: 4),\\n                        widget.subtitle!,\\n                      ],\\n                    ],\\n                  ),\\n                ),\\n                _NoteActions(\\n                  onEdit: _startInlineEdit,\\n                  onDelete: widget.onDelete,\\n                  isExpanded: _isExpanded,\\n                  onToggleExpansion: () {\\n                    setState(() {\\n                      _isExpanded = !_isExpanded;\\n                    });\\n                  },\\n                  extraAction: widget.extraAction,\\n                ),\\n              ],\\n            ),\\n          ),\\n        ),\\n        AnimatedSize(\\n          duration: const Duration(milliseconds: 200),\\n          curve: Curves.easeInOut,\\n          child: _isExpanded\\n              ? InkWell(\\n                  onTap: widget.onTap,\\n                  child: Container(\\n                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),\\n                    color: bgColor,\\n                    child: Align(\\n                      alignment: Alignment.centerRight,\\n                      child: PersonalNoteContentView(\\n                        note: widget.note,\\n                        textStyle: Theme.of(\\n                          context,\\n                        ).textTheme.bodyMedium?.copyWith(height: 1.5),\\n                        onLinkTap: widget.onLinkTap,\\n                      ),\\n                    ),\\n                  ),\\n                )\\n              : const SizedBox.shrink(),\\n        ),\\n        Divider(\\n          height: 1,\\n          thickness: 0.5,\\n          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),\\n        ),\\n      ],\\n    );\\n  }\\n\\n  @override\\n  void dispose() {\\n    _cancelRequest.dispose();\\n    super.dispose();\\n  }\\n}\\n\\nclass _NoteActions extends StatelessWidget {\\n  final VoidCallback onEdit;\\n  final VoidCallback onDelete;\\n  final bool isExpanded;\\n  final VoidCallback onToggleExpansion;\\n  final Widget? extraAction;\\n\\n  const _NoteActions({\\n    required this.onEdit,\\n    required this.onDelete,\\n    required this.isExpanded,\\n    required this.onToggleExpansion,\\n    this.extraAction,\\n  });\\n\\n  @override\\n  Widget build(BuildContext context) {\\n    return Row(\\n      mainAxisSize: MainAxisSize.min,\\n      children: [\\n        IconButton(\\n          tooltip: \'עריכה\',\\n          icon: const Icon(FluentIcons.edit_24_regular, size: 18),\\n          iconSize: 18,\\n          padding: const EdgeInsets.all(8),\\n          constraints: const BoxConstraints(\\n            minWidth: 32,\\n            minHeight: 32,\\n          ),\\n          onPressed: onEdit,\\n        ),\\n        ?extraAction,\\n        IconButton(\\n          tooltip: \'מחיקה\',\\n          icon: const Icon(FluentIcons.delete_24_regular, size: 18),\\n          iconSize: 18,\\n          padding: const EdgeInsets.all(8),\\n          constraints: const BoxConstraints(\\n            minWidth: 32,\\n            minHeight: 32,\\n          ),\\n          onPressed: onDelete,\\n        ),\\n        IconButton(\\n          tooltip: isExpanded ? \'סגור\' : \'פתח\',\\n          icon: AnimatedRotation(\\n            turns: isExpanded ? 0.5 : 0.0,\\n            duration: const Duration(milliseconds: 200),\\n            child: const Icon(\\n              FluentIcons.chevron_down_24_regular,\\n              size: 18,\\n            ),\\n          ),\\n          iconSize: 18,\\n          padding: const EdgeInsets.all(8),\\n          constraints: const BoxConstraints(\\n            minWidth: 32,\\n            minHeight: 32,\\n          ),\\n          onPressed: onToggleExpansion,\\n        ),\\n      ],\\n    );\\n  }\\n}\\n", "before_personal_note_editor.dart": "import \'dart:async\';\\nimport \'dart:convert\';\\nimport \'package:otzaria/theme/app_tokens.dart\';\\n\\nimport \'package:fluentui_system_icons/fluentui_system_icons.dart\';\\nimport \'package:otzaria_icons/otzaria_icons.dart\';\\nimport \'package:flutter/gestures.dart\';\\nimport \'package:flutter/material.dart\';\\nimport \'package:flutter/services.dart\';\\nimport \'package:flutter_quill/flutter_quill.dart\' as quill;\\nimport \'package:otzaria/personal_notes/models/personal_note.dart\';\\nimport \'package:otzaria/personal_notes/widgets/personal_note_link_dialog.dart\';\\nimport \'package:otzaria/shortcuts/shortcut_helper.dart\';\\nimport \'package:otzaria/widgets/misc/app_menu_exports.dart\';\\n\\n// LEFT/RIGHT swapped (flutter_quill doesn\'t flip them for RTL). UP/DOWN use\\n// Quill\'s adjacentLineAction: Windows input can\'t find lines across blocks.\\nconst _rtlArrowShortcuts = <ShortcutActivator, Intent>{\\n  // Horizontal navigation (RTL-swapped)\\n  SingleActivator(LogicalKeyboardKey.arrowRight):\\n      ExtendSelectionByCharacterIntent(forward: false, collapseSelection: true),\\n  SingleActivator(LogicalKeyboardKey.arrowLeft):\\n      ExtendSelectionByCharacterIntent(forward: true, collapseSelection: true),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowRight,\\n    shift: true,\\n  ): ExtendSelectionByCharacterIntent(\\n    forward: false,\\n    collapseSelection: false,\\n  ),\\n  SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):\\n      ExtendSelectionByCharacterIntent(forward: true, collapseSelection: false),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowRight,\\n    control: true,\\n  ): ExtendSelectionToNextWordBoundaryIntent(\\n    forward: false,\\n    collapseSelection: true,\\n  ),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowLeft,\\n    control: true,\\n  ): ExtendSelectionToNextWordBoundaryIntent(\\n    forward: true,\\n    collapseSelection: true,\\n  ),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowRight,\\n    control: true,\\n    shift: true,\\n  ): ExtendSelectionToNextWordBoundaryIntent(\\n    forward: false,\\n    collapseSelection: false,\\n  ),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowLeft,\\n    control: true,\\n    shift: true,\\n  ): ExtendSelectionToNextWordBoundaryIntent(\\n    forward: true,\\n    collapseSelection: false,\\n  ),\\n  // Vertical navigation (routed through Quill\'s adjacentLineAction)\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowUp,\\n  ): ExtendSelectionVerticallyToAdjacentLineIntent(\\n    forward: false,\\n    collapseSelection: true,\\n  ),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowDown,\\n  ): ExtendSelectionVerticallyToAdjacentLineIntent(\\n    forward: true,\\n    collapseSelection: true,\\n  ),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowUp,\\n    shift: true,\\n  ): ExtendSelectionVerticallyToAdjacentLineIntent(\\n    forward: false,\\n    collapseSelection: false,\\n  ),\\n  SingleActivator(\\n    LogicalKeyboardKey.arrowDown,\\n    shift: true,\\n  ): ExtendSelectionVerticallyToAdjacentLineIntent(\\n    forward: true,\\n    collapseSelection: false,\\n  ),\\n};\\n\\nclass PersonalNoteEditorResult {\\n  final String content;\\n  final String contentPlain;\\n  final PersonalNoteContentFormat contentFormat;\\n\\n  const PersonalNoteEditorResult({\\n    required this.content,\\n    required this.contentPlain,\\n    required this.contentFormat,\\n  });\\n}\\n\\nclass PersonalNoteEditorController {\\n  final quill.QuillController quillController;\\n\\n  PersonalNoteEditorController({required this.quillController});\\n\\n  PersonalNoteEditorResult buildResult() {\\n    final deltaJson = jsonEncode(quillController.document.toDelta().toJson());\\n    final plain = quillController.document.toPlainText().trimRight();\\n    return PersonalNoteEditorResult(\\n      content: deltaJson,\\n      contentPlain: plain,\\n      contentFormat: PersonalNoteContentFormat.quillDelta,\\n    );\\n  }\\n}\\n\\nclass PersonalNoteEditorBody extends StatefulWidget {\\n  final PersonalNoteEditorController controller;\\n  final FocusNode focusNode;\\n  final ScrollController scrollController;\\n  final bool autofocus;\\n  final String? referenceText;\\n  final String? hintText;\\n  final List<PersonalNote> linkableNotes;\\n  final String? bookId;\\n  final VoidCallback? onSaveShortcut;\\n\\n  const PersonalNoteEditorBody({\\n    super.key,\\n    required this.controller,\\n    required this.focusNode,\\n    required this.scrollController,\\n    required this.autofocus,\\n    required this.linkableNotes,\\n    this.referenceText,\\n    this.hintText,\\n    this.bookId,\\n    this.onSaveShortcut,\\n  });\\n\\n  @override\\n  State<PersonalNoteEditorBody> createState() => _PersonalNoteEditorBodyState();\\n}\\n\\nclass _PersonalNoteEditorBodyState extends State<PersonalNoteEditorBody> {\\n  final _editMenuKey = GlobalKey<AppContextMenuRegionState>();\\n  PointerDeviceKind? _lastPointerKind;\\n\\n  // עוטף את אזור הכתיבה כדי לגלול אותו לתוך התצוגה כשהוא יורד מתחת לחלון.\\n  final GlobalKey _editorAreaKey = GlobalKey();\\n  Timer? _settleTimer;\\n\\n  @override\\n  void initState() {\\n    super.initState();\\n    widget.focusNode.addListener(_handleFocusChange);\\n  }\\n\\n  @override\\n  void dispose() {\\n    _settleTimer?.cancel();\\n    widget.focusNode.removeListener(_handleFocusChange);\\n    super.dispose();\\n  }\\n\\n  void _handleFocusChange() {\\n    if (!widget.focusNode.hasFocus) return;\\n    // הפוקוס קודם לסוף אנימציית פתיחת הכרטיס והגלילה: גלילה ב-post-frame,\\n    // ושוב אחרי שהאנימציה (~200ms) מתייצבת, כדי לתפוס את המיקום הסופי.\\n    _scrollEditorIntoView();\\n    _settleTimer?.cancel();\\n    _settleTimer = Timer(\\n      const Duration(milliseconds: 250),\\n      _scrollEditorIntoView,\\n    );\\n  }\\n\\n  void _scrollEditorIntoView() {\\n    if (!mounted) return;\\n    WidgetsBinding.instance.addPostFrameCallback((_) {\\n      final ctx = _editorAreaKey.currentContext;\\n      if (ctx == null) return;\\n      // keepVisibleAtEnd גולל רק כשתחתית אזור הכתיבה מוסתרת; רק הרשימה העוטפת,\\n      // לא ה-PageView של כרטיסייה מוסתרת.\\n      Scrollable.maybeOf(ctx)?.position.ensureVisible(\\n        ctx.findRenderObject()!,\\n        duration: const Duration(milliseconds: 200),\\n        curve: Curves.easeInOut,\\n        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,\\n      );\\n    });\\n  }\\n\\n  /// Quill מבקש תפריט גם בסיום גרירה בעכבר, ושם לא מציגים כלום; לחיצה ימנית\\n  /// פותחת את התפריט מהאזור.\\n  Widget _touchContextMenu(\\n    BuildContext context,\\n    quill.QuillRawEditorState editorState,\\n  ) {\\n    if (_lastPointerKind\\n        case PointerDeviceKind.touch ||\\n            PointerDeviceKind.stylus ||\\n            PointerDeviceKind.invertedStylus) {\\n      WidgetsBinding.instance.addPostFrameCallback((_) {\\n        if (!mounted) return;\\n        editorState.hideToolbar(false);\\n        _editMenuKey.currentState?.openMenuAt(\\n          editorState.contextMenuAnchors.primaryAnchor,\\n        );\\n      });\\n    }\\n    return const SizedBox.shrink();\\n  }\\n\\n  List<AppContextMenuEntry> _buildEditMenu() {\\n    final controller = widget.controller.quillController;\\n    final hasSelection = !controller.selection.isCollapsed;\\n    final hasText = controller.document.length > 1;\\n    return [\\n      AppContextMenuEntry(\\n        label: \'גזור\',\\n        icon: FluentIcons.cut_24_regular,\\n        enabled: hasSelection,\\n        // ignore: experimental_member_use\\n        onTap: () => controller.clipboardSelection(false),\\n      ),\\n      AppContextMenuEntry(\\n        label: \'העתק\',\\n        icon: FluentIcons.copy_24_regular,\\n        enabled: hasSelection,\\n        // ignore: experimental_member_use\\n        onTap: () => controller.clipboardSelection(true),\\n      ),\\n      AppContextMenuEntry(\\n        label: \'הדבק\',\\n        icon: FluentIcons.clipboard_paste_24_regular,\\n        // ignore: experimental_member_use\\n        onTap: controller.clipboardPaste,\\n      ),\\n      AppContextMenuEntry(\\n        label: \'בחר הכל\',\\n        icon: FluentIcons.select_all_on_24_regular,\\n        enabled: hasText,\\n        onTap: () => controller.updateSelection(\\n          TextSelection(\\n            baseOffset: 0,\\n            extentOffset: controller.document.length - 1,\\n          ),\\n          quill.ChangeSource.local,\\n        ),\\n      ),\\n    ];\\n  }\\n\\n  Future<void> _insertLink() async {\\n    final result = await showDialog<PersonalNoteLinkTarget>(\\n      context: context,\\n      builder: (context) => PersonalNoteLinkDialog(\\n        bookId: widget.bookId,\\n        notes: widget.linkableNotes,\\n      ),\\n    );\\n    if (result == null) return;\\n\\n    final controller = widget.controller.quillController;\\n    final selection = controller.selection;\\n\\n    if (!selection.isCollapsed) {\\n      controller.formatSelection(quill.LinkAttribute(result.url));\\n      return;\\n    }\\n\\n    final insertText = result.label.isNotEmpty ? result.label : result.url;\\n    final index = selection.baseOffset;\\n    controller.document.insert(index, insertText);\\n    controller.updateSelection(\\n      TextSelection.collapsed(offset: index + insertText.length),\\n      quill.ChangeSource.local,\\n    );\\n    controller.formatText(\\n      index,\\n      insertText.length,\\n      quill.LinkAttribute(result.url),\\n    );\\n  }\\n\\n  @override\\n  Widget build(BuildContext context) {\\n    final colorScheme = Theme.of(context).colorScheme;\\n    final referenceStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(\\n      fontWeight: FontWeight.w500,\\n      color: colorScheme.onSurfaceVariant,\\n    );\\n    // מגבילים את טקסט ההקשר ל~3 שורות + גלילה פנימית, כדי שטקסט נבחר ארוך\\n    // לא ידחוף את אזור הכתיבה מטה ומחוץ למסך. הגובה נגזר מסגנון הטקסט בפועל.\\n    final referenceMaxHeight =\\n        (referenceStyle?.fontSize ?? 14) * (referenceStyle?.height ?? 1.4) * 3;\\n    return Column(\\n      mainAxisSize: MainAxisSize.min,\\n      children: [\\n        if (widget.referenceText != null &&\\n            widget.referenceText!.trim().isNotEmpty)\\n          Container(\\n            padding: const EdgeInsets.all(12),\\n            decoration: BoxDecoration(\\n              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),\\n              borderRadius: AppTokens.borderRadiusAll,\\n            ),\\n            child: ConstrainedBox(\\n              constraints: BoxConstraints(maxHeight: referenceMaxHeight),\\n              child: SingleChildScrollView(\\n                child: Text(\\n                  widget.referenceText!,\\n                  style: referenceStyle,\\n                  textAlign: TextAlign.right,\\n                ),\\n              ),\\n            ),\\n          ),\\n        Container(\\n          key: _editorAreaKey,\\n          decoration: BoxDecoration(\\n            border: Border.all(\\n              color: colorScheme.outline.withValues(alpha: 0.6),\\n              width: 1.2,\\n            ),\\n            borderRadius: AppTokens.borderRadiusAll,\\n          ),\\n          child: Column(\\n            children: [\\n              _PersonalNoteToolbar(\\n                controller: widget.controller.quillController,\\n                editorFocusNode: widget.focusNode,\\n                onInsertLink: _insertLink,\\n              ),\\n              const Divider(height: 1),\\n              SizedBox(\\n                // במסך נמוך או עם מקלדת פתוחה 220px קבועים דוחקים את כפתור\\n                // השמירה מחוץ לתצוגה — מצמצמים לפי הגובה הפנוי בפועל.\\n                height: () {\\n                  final media = MediaQuery.of(context);\\n                  final available = media.size.height - media.viewInsets.bottom;\\n                  return (available * 0.35).clamp(120.0, 220.0);\\n                }(),\\n                // תופס גרירה אנכית לפני ה-ListView של הפאנל, שאחרת גובר\\n                // על גרירת הסימון של Quill; הגלגלת (PointerSignal) עדיין גוללת.\\n                child: RawGestureDetector(\\n                  behavior: HitTestBehavior.translucent,\\n                  gestures: <Type, GestureRecognizerFactory>{\\n                    VerticalDragGestureRecognizer:\\n                        GestureRecognizerFactoryWithHandlers<\\n                          VerticalDragGestureRecognizer\\n                        >(\\n                          () => VerticalDragGestureRecognizer(\\n                            supportedDevices: const <PointerDeviceKind>{\\n                              PointerDeviceKind.mouse,\\n                            },\\n                          ),\\n                          (instance) {},\\n                        ),\\n                  },\\n                  child: CallbackShortcuts(\\n                    bindings: {\\n                      if (widget.onSaveShortcut != null) ...{\\n                        // Ctrl+Enter (במק Cmd+Enter) — קיצור השמירה המומלץ.\\n                        ShortcutHelper.activatorFromShortcut(\'ctrl+enter\')!:\\n                            widget.onSaveShortcut!,\\n                        // Alt+Enter — לתאימות לאחור; ב-Windows הוא משמיע\\n                        // \\"דינג\\" מערכת, ולכן הקיצור הראשי הוא Ctrl+Enter.\\n                        const SingleActivator(\\n                          LogicalKeyboardKey.enter,\\n                          alt: true,\\n                        ): widget.onSaveShortcut!,\\n                      },\\n                    },\\n                    child: AppContextMenuRegion(\\n                      key: _editMenuKey,\\n                      // לחיצה ארוכה של Quill גוברת על זו של האזור; במגע התפריט\\n                      // נפתח מ-contextMenuBuilder.\\n                      openOnLongPress: false,\\n                      menuBuilder: (_, _) => _buildEditMenu(),\\n                      child: Listener(\\n                        onPointerDown: (event) => _lastPointerKind = event.kind,\\n                        // Quill לא מבקש פוקוס בגרירת בחירה בעכבר, ובלעדיו\\n                        // מחיקה והעתקה של הבחירה לא מגיעות לעורך.\\n                        onPointerUp: (event) {\\n                          if (event.kind == PointerDeviceKind.mouse &&\\n                              !widget.focusNode.hasFocus) {\\n                            widget.focusNode.requestFocus();\\n                          }\\n                        },\\n                        child: quill.QuillEditor(\\n                          controller: widget.controller.quillController,\\n                          focusNode: widget.focusNode,\\n                          scrollController: widget.scrollController,\\n                          config: quill.QuillEditorConfig(\\n                            autoFocus: widget.autofocus,\\n                            expands: false,\\n                            padding: const EdgeInsets.all(12),\\n                            placeholder:\\n                                widget.hintText ??\\n                                \'כתוב כאן... (${ShortcutHelper.formatShortcutForDisplay(\'ctrl+enter\')} לשמירה)\',\\n                            customShortcuts: _rtlArrowShortcuts,\\n                            contextMenuBuilder: _touchContextMenu,\\n                          ),\\n                        ),\\n                      ),\\n                    ),\\n                  ),\\n                ),\\n              ),\\n            ],\\n          ),\\n        ),\\n      ],\\n    );\\n  }\\n}\\n\\n// בלי ביטול הדבקת Rich-Text, ה-HTML שהעתקת אוצריא שמה בלוח גורר את עיצוב\\n// הספר לתוך ההערה ולטקסט שיוקלד אחריו.\\n// ignore: experimental_member_use\\nconst _noteClipboardConfig = quill.QuillClipboardConfig(\\n  // ignore: experimental_member_use\\n  enableExternalRichPaste: false,\\n);\\nconst _noteControllerConfig = quill.QuillControllerConfig(\\n  // ignore: experimental_member_use\\n  clipboardConfig: _noteClipboardConfig,\\n);\\n\\nPersonalNoteEditorController buildPersonalNoteEditorController({\\n  required String initialContent,\\n  required PersonalNoteContentFormat initialFormat,\\n}) {\\n  if (initialFormat == PersonalNoteContentFormat.quillDelta &&\\n      initialContent.trim().isNotEmpty) {\\n    try {\\n      final decoded = jsonDecode(initialContent) as List<dynamic>;\\n      final document = quill.Document.fromJson(decoded);\\n      return PersonalNoteEditorController(\\n        quillController: quill.QuillController(\\n          document: document,\\n          selection: const TextSelection.collapsed(offset: 0),\\n          config: _noteControllerConfig,\\n        ),\\n      );\\n    } catch (_) {}\\n  }\\n\\n  final document = quill.Document()\\n    ..insert(0, initialContent.trimRight().isEmpty ? \'\' : \'$initialContent\\\\n\');\\n  return PersonalNoteEditorController(\\n    quillController: quill.QuillController(\\n      document: document,\\n      selection: const TextSelection.collapsed(offset: 0),\\n      config: _noteControllerConfig,\\n    ),\\n  );\\n}\\n\\nclass _PersonalNoteToolbar extends StatelessWidget {\\n  final quill.QuillController controller;\\n  final FocusNode editorFocusNode;\\n  final VoidCallback onInsertLink;\\n\\n  const _PersonalNoteToolbar({\\n    required this.controller,\\n    required this.editorFocusNode,\\n    required this.onInsertLink,\\n  });\\n\\n  static const double _minFontSize = 12;\\n  static const double _maxFontSize = 32;\\n  static const double _defaultFontSize = 16;\\n  static const double _fontSizeStep = 2;\\n\\n  void _toggleAttribute(quill.Attribute attribute) {\\n    final selectedAttributes = controller.getSelectionStyle().attributes;\\n    final isActive = _isAttributeActive(attribute, selectedAttributes);\\n    controller\\n      ..skipRequestKeyboard = !attribute.isInline\\n      ..formatSelection(\\n        isActive ? quill.Attribute.clone(attribute, null) : attribute,\\n      );\\n    // הכפתור גוזל את הפוקוס, ו-Quill בדסקטופ אינו מחזיר אותו; בלעדיו הסמן\\n    // נעלם וטקסט שיוקלד לא יקבל את ה-toggledStyle.\\n    editorFocusNode.requestFocus();\\n  }\\n\\n  double _currentFontSize() {\\n    final value = controller\\n        .getSelectionStyle()\\n        .attributes[quill.Attribute.size.key]\\n        ?.value;\\n    if (value is num) return value.toDouble();\\n    if (value is String) return double.tryParse(value) ?? _defaultFontSize;\\n    return _defaultFontSize;\\n  }\\n\\n  void _adjustFontSize(double delta) {\\n    final newSize = (_currentFontSize() + delta).clamp(\\n      _minFontSize,\\n      _maxFontSize,\\n    );\\n    controller.formatSelection(\\n      quill.Attribute.fromKeyValue(quill.Attribute.size.key, newSize),\\n    );\\n    editorFocusNode.requestFocus();\\n  }\\n\\n  bool _isAttributeActive(\\n    quill.Attribute attribute,\\n    Map<String, quill.Attribute> selectedAttributes,\\n  ) {\\n    if (attribute.key == quill.Attribute.list.key ||\\n        attribute.key == quill.Attribute.header.key ||\\n        attribute.key == quill.Attribute.script.key ||\\n        attribute.key == quill.Attribute.align.key ||\\n        attribute.key == quill.Attribute.background.key) {\\n      final selectedAttribute = selectedAttributes[attribute.key];\\n      return selectedAttribute?.value == attribute.value;\\n    }\\n\\n    return selectedAttributes.containsKey(attribute.key);\\n  }\\n\\n  @override\\n  Widget build(BuildContext context) {\\n    return Wrap(\\n      spacing: 4,\\n      children: [\\n        IconButton(\\n          tooltip: \'מודגש\',\\n          icon: const Icon(FluentIcons.text_bold_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(quill.Attribute.bold),\\n        ),\\n        IconButton(\\n          tooltip: \'נטוי\',\\n          icon: const Icon(FluentIcons.text_italic_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(quill.Attribute.italic),\\n        ),\\n        IconButton(\\n          tooltip: \'קו תחתי\',\\n          icon: const Icon(FluentIcons.text_underline_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(quill.Attribute.underline),\\n        ),\\n        IconButton(\\n          tooltip: \'קו חוצה\',\\n          icon: const Icon(FluentIcons.text_strikethrough_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(quill.Attribute.strikeThrough),\\n        ),\\n        IconButton(\\n          tooltip: \'הדגשה\',\\n          icon: const Icon(FluentIcons.circle_highlight_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(\\n            const quill.BackgroundAttribute(\'#fff59d\'),\\n          ),\\n        ),\\n        IconButton(\\n          tooltip: \'הגדל כתב\',\\n          icon: const Icon(FluentIcons.font_increase_24_regular, size: 18),\\n          onPressed: () => _adjustFontSize(_fontSizeStep),\\n        ),\\n        IconButton(\\n          tooltip: \'הקטן כתב\',\\n          icon: const Icon(FluentIcons.font_decrease_24_regular, size: 18),\\n          onPressed: () => _adjustFontSize(-_fontSizeStep),\\n        ),\\n        IconButton(\\n          tooltip: \'כותרת\',\\n          icon: const Icon(FluentIcons.text_header_2_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(quill.Attribute.h2),\\n        ),\\n        IconButton(\\n          tooltip: \'רשימה\',\\n          icon: const Icon(OtzariaIcons.text_bullet_list_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(quill.Attribute.ul),\\n        ),\\n        IconButton(\\n          tooltip: \'רשימה ממוספרת\',\\n          icon: const Icon(\\n            OtzariaIcons.text_number_list_24_regular,\\n            size: 18,\\n          ),\\n          onPressed: () => _toggleAttribute(quill.Attribute.ol),\\n        ),\\n        IconButton(\\n          tooltip: \'ציטוט\',\\n          icon: const Icon(FluentIcons.text_quote_24_regular, size: 18),\\n          onPressed: () => _toggleAttribute(quill.Attribute.blockQuote),\\n        ),\\n        IconButton(\\n          tooltip: \'הוסף קישור\',\\n          icon: const Icon(OtzariaIcons.link_24_regular, size: 18),\\n          onPressed: onInsertLink,\\n        ),\\n      ],\\n    );\\n  }\\n}\\n"}')

BASE = 'f4085b9efa12dbf6800c8641b0c5d52342a192ee'
EXPECTED_PRODUCT_TREE = '56c248c7cd482d9fbe8310fea333e593fb329d7e'
REPO = Path(os.environ.get('GITHUB_WORKSPACE', os.getcwd())).resolve()
OUT = Path(os.environ.get('RUNNER_TEMP', tempfile.gettempdir())) / 'personal-notes-qa'
FLUTTER = shutil.which('flutter')
DART = shutil.which('dart')
ENV = {**os.environ, 'OTZARIA_REQUIRE_SEARCH_ENGINE': '1', 'TZ': 'Asia/Jerusalem'}
RED_SOURCES = [
    'lib/text_book/view/page_shape/page_shape_screen.dart',
    'lib/text_book/view/splited_view/splited_view_screen.dart',
]
CALLER_TESTS = [
    'test/text_book/view/page_shape/page_shape_screen_settings_test.dart',
    'test/text_book/view/splited_view_toggle_commentators_pane_test.dart',
]
GREEN_TESTS = [
    'test/personal_notes/',
    'test/text_book/utils/note_inline_render_test.dart',
    'test/text_book/view/combined_view/combined_book_screen_test.dart',
    'test/text_book/view/page_shape/simple_text_viewer_test.dart',
    'test/text_book/view/page_shape/simple_text_viewer_notes_sync_test.dart',
    *CALLER_TESTS,
]
MANIFEST = {
    'base': BASE,
    'expected_product_tree': EXPECTED_PRODUCT_TREE,
    'expected_hashes': EXPECTED_HASHES,
    'environment': {'OTZARIA_REQUIRE_SEARCH_ENGINE': '1', 'TZ': 'Asia/Jerusalem'},
    'hash_checks': [],
    'stages': [],
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def save_manifest() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    temporary = OUT / 'source-hashes.tmp'
    temporary.write_text(json.dumps(MANIFEST, indent=2, ensure_ascii=False))
    temporary.replace(OUT / 'source-hashes.json')


def check_hashes(label: str, expected: dict[str, str] | None = None) -> None:
    expected = EXPECTED_HASHES if expected is None else expected
    actual = {
        name: sha((REPO / name).read_bytes()) if (REPO / name).is_file() else None
        for name in expected
    }
    mismatches = [name for name in expected if actual[name] != expected[name]]
    MANIFEST['hash_checks'].append({
        'label': label, 'actual': actual, 'mismatches': mismatches,
        'baseline_overrides': {name: value for name, value in expected.items()
                               if value != EXPECTED_HASHES[name]},
    })
    save_manifest()
    if mismatches:
        raise RuntimeError(f'Source hashes differ at {label}: {mismatches}')
    print(f'{label}: all {len(expected)} source hashes match.', flush=True)


def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def run_stage(name: str, args: list[str], timeout: int,
              expected: dict[str, str] | None = None) -> tuple[int, str]:
    check_hashes(f'before-{name}', expected)
    path = OUT / f'{name}.log'
    print(f'{name}: started; log={path}', flush=True)
    started = time.monotonic()
    report = {'name': name, 'command': args, 'log': str(path), 'timed_out': False}
    MANIFEST['stages'].append(report)
    save_manifest()
    process = None
    code = None
    try:
        with path.open('w') as log:
            log.write('command=' + json.dumps(args, ensure_ascii=False) + '\n')
            log.write('OTZARIA_REQUIRE_SEARCH_ENGINE=1, TZ=Asia/Jerusalem\n')
            log.flush()
            process = subprocess.Popen(
                args, cwd=REPO, env=ENV, stdout=log, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                report['timed_out'] = True
                stop_process(process)
                code = 124
                log.write(f'\nStage timed out after {timeout} seconds.\n')
            except BaseException:
                stop_process(process)
                raise
    finally:
        report['exit_code'] = code
        report['seconds'] = round(time.monotonic() - started, 2)
        save_manifest()
        check_hashes(f'after-{name}', expected)
    output = path.read_text(errors='replace')
    print(f'{name}: exit={code}, seconds={report["seconds"]}', flush=True)
    for line in output.splitlines()[-14:]:
        print(line, flush=True)
    return code, output


def prepare_file(source: Path, data: bytes, label: str) -> Path:
    with tempfile.NamedTemporaryFile(
        mode='wb', prefix=f'.{source.name}.qa-{label}-', suffix='.tmp',
        dir=source.parent, delete=False,
    ) as file:
        name = Path(file.name)
        try:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        except BaseException:
            name.unlink(missing_ok=True)
            raise
    os.chmod(name, source.stat().st_mode & 0o777)
    if name.read_bytes() != data:
        name.unlink(missing_ok=True)
        raise RuntimeError(f'Incomplete {label} checkpoint for {source}')
    return name


def red_proof(test_command: list[str]) -> None:
    check_hashes('before-baseline-preparation')
    originals = {}
    baselines = {}
    temporary_files = []
    swapped = False
    baseline_expected = dict(EXPECTED_HASHES)
    try:
        for name in RED_SOURCES:
            source = REPO / name
            original = prepare_file(source, source.read_bytes(), 'original')
            originals[name] = original
            temporary_files.append(original)
            data = subprocess.check_output(['git', 'show', f'{BASE}:{name}'], cwd=REPO)
            baseline = prepare_file(source, data, 'baseline')
            baselines[name] = baseline
            temporary_files.append(baseline)
            baseline_expected[name] = sha(data)
        swapped = True
        for name in RED_SOURCES:
            os.replace(baselines[name], REPO / name)
        code, output = run_stage(
            '02-callers-red',
            [*test_command, *CALLER_TESTS, '--plain-name', 'לחיצה חוזרת על הערת מפרש'],
            900, baseline_expected,
        )
    finally:
        if swapped:
            for name in RED_SOURCES:
                os.replace(originals[name], REPO / name)
        for temporary in temporary_files:
            temporary.unlink(missing_ok=True)
        check_hashes('after-atomic-baseline-restore')
    expected_failures = [
        'לחיצה חוזרת על הערת מפרש מבקשת לחשוף אותה שוב [E]',
        'לחיצה חוזרת על הערת מפרש משמרת מקור ומבקשת חשיפה [E]',
    ]
    valid = (
        code == 1
        and '+0 -2: Some tests failed.' in output
        and all(name in output for name in expected_failures)
        and output.count('The following TestFailure was thrown running a test:') == 2
        and output.count('Actual: []') >= 2
        and 'pumpAndSettle timed out' not in output
        and 'TimeoutException' not in output
    )
    MANIFEST['red_proof_valid'] = valid
    save_manifest()
    if not valid:
        raise RuntimeError('Red proof did not fail solely on the two missing repeated-click events.')


def prepare_captures() -> Path:
    check_hashes('before-capture-preparation')
    directory = OUT / 'captures'
    directory.mkdir(parents=True, exist_ok=True)
    before_sources = {
        'before_note_tile.dart': 'lib/personal_notes/widgets/note_tile.dart',
        'before_personal_note_editor.dart': 'lib/personal_notes/widgets/personal_note_editor.dart',
    }
    for filename, source in before_sources.items():
        baseline = subprocess.check_output(['git', 'show', f'{BASE}:{source}'], cwd=REPO)
        if CAPTURE_SOURCES[filename].encode() != baseline:
            raise RuntimeError(f'Embedded before capture differs from baseline: {filename}')
    helper_uri = (REPO / 'test/test_helpers/memory_cache_provider.dart').as_uri()
    output_path = directory.as_posix().replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    for filename, content in CAPTURE_SOURCES.items():
        content = content.replace('__MEMORY_CACHE_HELPER_URI__', helper_uri)
        content = content.replace('__CAPTURE_OUTPUT_DIR__', output_path)
        (directory / filename).write_text(content)
    check_hashes('after-capture-preparation')
    return directory / 'personal_notes_ui_capture_test.dart'


def main() -> int:
    save_manifest()
    if FLUTTER is None or DART is None:
        raise RuntimeError('Flutter and Dart must be on PATH.')
    MANIFEST['head_commit'] = git('rev-parse', 'HEAD')
    MANIFEST['product_commit'] = git('rev-parse', 'HEAD^')
    MANIFEST['product_tree'] = git('rev-parse', 'HEAD^1^{tree}')
    if MANIFEST['product_tree'] != EXPECTED_PRODUCT_TREE:
        raise RuntimeError('The validation commit parent is not the exact product candidate tree.')
    save_manifest()
    code, _ = run_stage(
        '00-format',
        [DART, 'format', '--output=none', '--set-exit-if-changed', *EXPECTED_HASHES],
        120,
    )
    if code:
        return code
    test_command = [FLUTTER, 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded']
    code, _ = run_stage(
        '01-word-fixture',
        [*test_command, 'test/personal_notes/personal_notes_word_export_screen_test.dart'],
        900,
    )
    if code:
        return code
    red_proof(test_command)
    code, _ = run_stage('03-green', [*test_command, *GREEN_TESTS], 1800)
    if code:
        return code
    capture_test = prepare_captures()
    code, _ = run_stage('04-ui-captures', [*test_command, str(capture_test)], 900)
    if code:
        return code
    code, _ = run_stage('05-analyze', [FLUTTER, 'analyze', '--no-pub'], 900)
    if code:
        return code
    check_hashes('final-candidate')
    MANIFEST['git_status'] = git('status', '--porcelain')
    if MANIFEST['git_status']:
        raise RuntimeError('The validation run left repository changes.')
    return 0


def interrupted(signum: int, frame: object) -> None:
    raise KeyboardInterrupt(f'Signal {signum}')


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    exit_code = 1
    try:
        exit_code = main()
    except BaseException as error:
        MANIFEST['error'] = f'{type(error).__name__}: {error}'
        print(MANIFEST['error'], flush=True)
    finally:
        MANIFEST['exit_code'] = exit_code
        save_manifest()
    sys.exit(exit_code)
