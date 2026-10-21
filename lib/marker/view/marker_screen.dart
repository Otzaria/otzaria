import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/marker/bloc/marker_bloc.dart';
import 'package:otzaria/marker/bloc/marker_event.dart';
import 'package:otzaria/marker/bloc/marker_state.dart';
import 'package:otzaria/marker/legacy/legacy_marker_plugin.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/models/marker_text.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_export.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/view/marker_file_actions.dart';
import 'package:otzaria/marker/view/marker_navigation.dart';
import 'package:otzaria/marker/view/widgets/marker_books_pane.dart';
import 'package:otzaria/marker/view/widgets/marker_dialogs.dart';
import 'package:otzaria/marker/view/widgets/marker_filter_bar.dart';
import 'package:otzaria/marker/view/widgets/marker_tags_dialog.dart';
import 'package:otzaria/marker/view/widgets/marker_tile.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/panels/marker_settings_panel.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/tool_query.dart';
import 'package:otzaria/utils/ui/editable_focus.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// מסך הכלי "מרקר": כל הסימונים, עם חיפוש, סינון, עריכה, ייצוא וייבוא.
class MarkerScreen extends StatelessWidget {
  const MarkerScreen({super.key, this.repository, this.queryInbox});

  @visibleForTesting
  final MarkerRepository? repository;

  /// חיפוש שהגיע מקישור ישיר (`otzaria://open/marker?q=`).
  final ToolQueryInbox? queryInbox;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        MarkerBloc(repository: repository)..add(const MarkerStarted()),
    child: _MarkerView(queryInbox: queryInbox),
  );
}

enum _FileAction {
  print,
  word,
  backup,
  importFile,
  importPlugin,
  tags,
}

class _MarkerView extends StatefulWidget {
  const _MarkerView({this.queryInbox});

  final ToolQueryInbox? queryInbox;

  @override
  State<_MarkerView> createState() => _MarkerViewState();
}

class _MarkerViewState extends State<_MarkerView>
    with ToolQueryConsumer<_MarkerView> {
  static const String _legacySeenKey = 'key-marker-legacy-seen';

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  Timer? _searchDebounce;
  bool _booksPaneOpen = false;
  bool _settingsOpen = false;
  bool _selecting = false;
  String? _focusedId;
  int _legacyCount = 0;

  MarkerBloc get _bloc => context.read<MarkerBloc>();

  @override
  ToolQueryInbox? get toolQueryInbox => widget.queryInbox;

  @override
  void applyToolQuery(ToolQuery query) {
    fillSearchField(_search, query.text);
    final current = _bloc.state.query;
    _query(
      MarkerQuery(
        search: query.text,
        sort: current.sort,
        group: current.group,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    markerFocusRequest.addListener(_applyFocusRequest);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyFocusRequest();
      unawaited(_checkLegacyPlugin());
    });
  }

  @override
  void dispose() {
    markerFocusRequest.removeListener(_applyFocusRequest);
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// הצגת סימון מבוקש: הרשימה מצטמצמת לספר שלו ולטקסט שלו, והוא מודגש.
  void _applyFocusRequest() {
    final mark = markerFocusRequest.value;
    if (mark == null || !mounted) return;
    markerFocusRequest.value = null;
    final search = truncateGraphemes(mark.text, 30);
    _search.text = search;
    setState(() => _focusedId = mark.id);
    _query(
      MarkerQuery(
        search: search,
        bookTitle: mark.bookTitle,
        bookPdf: mark.pdf,
        sort: _bloc.state.query.sort,
        group: _bloc.state.query.group,
      ),
      keepFocus: true,
    );
  }

  Future<void> _checkLegacyPlugin() async {
    final List<String> keys;
    try {
      keys = await PluginRegistryRepository().listKVKeys(
        kLegacyMarkerPluginId,
        'default',
      );
    } catch (error) {
      debugPrint('Marker: reading legacy plugin keys failed: $error');
      return;
    }
    final count = keys.where((key) => key.startsWith('highlight:')).length;
    final seen = Settings.getValue<int>(_legacySeenKey) ?? 0;
    if (mounted && count > seen) setState(() => _legacyCount = count);
  }

  void _dismissLegacy() {
    Settings.setValue<int>(_legacySeenKey, _legacyCount);
    setState(() => _legacyCount = 0);
  }

  /// רק בלחיצת המשתמש ואחרי אישור; התוסף ונתוניו נשארים, ואפשר להפעילו שוב
  /// בניהול הכלים.
  Future<void> _disableLegacyPlugin() async {
    final confirmed = await confirmMarkerAction(
      context,
      title: 'השבתת התוסף הישן',
      content:
          'התוסף יושבת ונתוניו יישארו כפי שהם. אפשר להפעיל אותו שוב '
          'בהגדרות ← כלים ← ניהול תוספים.',
      confirmText: 'השבתה',
    );
    if (!confirmed || !mounted) return;
    context.read<PluginSystemBloc>().add(
      const DisablePluginRequested(kLegacyMarkerPluginId),
    );
  }

  /// נקרא ב-build: ההשבתה מסתיימת אחרי טעינה מחדש של התוספים, והבאנר
  /// מתעדכן איתה.
  bool get _legacyPluginEnabled => context.select(
    (PluginSystemBloc bloc) => switch (bloc.state) {
      final PluginSystemLoaded state => state.plugins.any(
        (plugin) => plugin.pluginId == kLegacyMarkerPluginId && plugin.enabled,
      ),
      _ => false,
    },
  );

  void _onScroll() {
    final state = _bloc.state;
    if (!state.hasMore || state.loadingMore) return;
    if (_scroll.position.extentAfter < 800) {
      _bloc.add(const MarkerMoreRequested());
    }
  }

  /// [keepFocus] — רק כשהשאילתה נועדה להראות את הסימון שהתבקש.
  void _query(MarkerQuery query, {bool keepFocus = false}) {
    // חיפוש שהוקלד ועוד לא הוחל נשמר כשבוחרים מסנן אחר מיד אחריו.
    if ((_searchDebounce?.isActive ?? false) &&
        query.search == _bloc.state.query.search) {
      query = query.copyWith(search: _search.text);
    }
    _searchDebounce?.cancel();
    if (!keepFocus && _focusedId != null) setState(() => _focusedId = null);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // "הכול" מנקה גם את החיפוש, ולכן השדה מתעדכן לפי השאילתה.
    if (_search.text != query.search) _search.text = query.search;
    _bloc.add(MarkerQueryChanged(query));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _query(_bloc.state.query.copyWith(search: value));
    });
  }

  /// כל הסימונים שהפעולה חלה עליהם: הנבחרים, ואחרת כל מה שמתאים לסינון
  /// (גם מה שעוד לא נטען לרשימה).
  Future<List<MarkerHighlight>> _scope() async {
    final state = _bloc.state;
    if (state.selectedIds.isNotEmpty) {
      return [
        for (final item in state.items)
          if (state.selectedIds.contains(item.id)) item,
      ];
    }
    return MarkerActions.instance.matching(
      state.query,
      colorOrder: [
        for (final color in MarkerSettings.instance.palette.colors) color.id,
      ],
    );
  }

  Future<void> _onFileAction(_FileAction action) async {
    try {
      await _runFileAction(action);
    } catch (error, stackTrace) {
      // הפעולות עצמן מדווחות על כשל; כאן נתפס כשל בקריאת הסימונים לפניהן.
      debugPrint('Marker file action $action failed: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);
      UiSnack.showError(MarkerMessages.loadFailed);
    }
  }

  Future<void> _runFileAction(_FileAction action) async {
    switch (action) {
      case _FileAction.print:
        final scope = await _scope();
        if (mounted) await printMarkerHighlights(context, scope);
      case _FileAction.word:
        final scope = await _scope();
        if (mounted) await exportMarkerToWord(context, scope);
      case _FileAction.backup:
        final selected = _bloc.state.selectedIds.isEmpty
            ? null
            : await _scope();
        if (mounted) await backupMarkerToFile(context, only: selected);
      case _FileAction.importFile:
        await importMarkerFromFile(context);
      case _FileAction.importPlugin:
        await importMarkerFromLegacyPlugin(context);
        if (mounted && _legacyCount > 0) _dismissLegacy();
      case _FileAction.tags:
        await showMarkerTagsDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchShortcut = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts[ShortcutValidator.currentWindowSearchKey] ??
          ShortcutValidator.defaultShortcuts[ShortcutValidator
              .currentWindowSearchKey] ??
          'ctrl+f',
    );
    return CallbackShortcuts(
      bindings: {
        ShortcutHelper.activatorFromShortcut(searchShortcut) ??
                const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onListKey,
        child: ListenableBuilder(
          listenable: MarkerSettings.instance,
          builder: (context, _) => BlocBuilder<MarkerBloc, MarkerState>(
            builder: (context, state) => Column(
              children: [
                _topBar(context, state),
                Expanded(
                  child: Stack(
                    children: [
                      NavSidePanel(
                        isOpen: _booksPaneOpen,
                        onClose: () => setState(() => _booksPaneOpen = false),
                        onOpen: () => setState(() => _booksPaneOpen = true),
                        minMainContentWidth: 320,
                        paneContent: MarkerBooksPane(
                          books: state.books,
                          total: state.counts.total,
                          selected: state.query.bookTitle == null
                              ? null
                              : (
                                  title: state.query.bookTitle!,
                                  pdf: state.query.bookPdf,
                                ),
                          onSelected: (book) => _query(
                            state.query.copyWith(
                              bookTitle: () => book?.title,
                              bookPdf: book?.pdf ?? false,
                            ),
                          ),
                        ),
                        mainContent: _content(context, state),
                      ),
                      ContextOverlayPanel(
                        isOpen: _settingsOpen,
                        onClose: () => setState(() => _settingsOpen = false),
                        title: 'הגדרות',
                        scrollable: true,
                        child: const MarkerSettingsPanel(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, MarkerState state) {
    final compact = context.select(
      (SettingsBloc bloc) => bloc.state.compactMenuMode,
    );
    final query = state.query;
    // בטלפון המיון והקיבוץ בתפריט אחד, כדי שלחיפוש יישאר מקום.
    final narrow = MediaQuery.sizeOf(context).width < 480;
    const sorts = [
      AppMenuEntry(value: MarkerSort.newest, label: 'מהחדש לישן'),
      AppMenuEntry(value: MarkerSort.oldest, label: 'מהישן לחדש'),
      AppMenuEntry(value: MarkerSort.book, label: 'לפי ספר ומקום'),
      AppMenuEntry(value: MarkerSort.color, label: 'לפי צבע'),
      AppMenuEntry(value: MarkerSort.favorites, label: 'מועדפים תחילה'),
    ];
    const groups = [
      AppMenuEntry(value: MarkerGroup.none, label: 'ללא קיבוץ'),
      AppMenuEntry(value: MarkerGroup.book, label: 'לפי ספר'),
      AppMenuEntry(value: MarkerGroup.color, label: 'לפי צבע'),
      AppMenuEntry(value: MarkerGroup.date, label: 'לפי תאריך'),
    ];
    AppMenuEntry<Object> checked(AppMenuEntry<Object> entry, bool on) =>
        AppMenuEntry(
          value: entry.value,
          label: entry.label,
          icon: on
              ? FluentIcons.checkmark_24_regular
              : FluentIcons.circle_small_24_regular,
        );
    return AppTopBar(
      leadingItems: [
        AppTopBarItem(
          widget: NavPanelToggleButton(
            isOpen: _booksPaneOpen,
            onToggle: () => setState(() => _booksPaneOpen = !_booksPaneOpen),
          ),
        ),
      ],
      center: OtzariaSearchField(
        controller: _search,
        focusNode: _searchFocus,
        hintText: 'חיפוש בסימונים, בהערות ובתגיות',
        onChanged: _onSearchChanged,
        onClear: () {
          _onSearchChanged('');
          setState(() => _focusedId = null);
        },
      ),
      trailingItems: [
        if (narrow)
          AppTopBarItem(
            widget: AppPopupMenuButton<Object>(
              tooltip: 'מיון וקיבוץ',
              iconData: FluentIcons.arrow_sort_24_regular,
              highlighted: query.group != MarkerGroup.none,
              onSelected: (value) => _query(switch (value) {
                MarkerSort sort => query.copyWith(sort: sort),
                MarkerGroup group => query.copyWith(group: group),
                _ => query,
              }),
              entries: [
                for (final entry in sorts)
                  checked(entry, entry.value == query.sort),
                for (final entry in groups)
                  checked(
                    AppMenuEntry(
                      value: entry.value,
                      label: entry.value == MarkerGroup.none
                          ? entry.label
                          : 'קיבוץ ${entry.label}',
                    ),
                    entry.value == query.group,
                  ),
              ],
            ),
          )
        else ...[
          AppTopBarItem(
            widget: AppPopupMenuButton<MarkerSort>(
              tooltip: 'מיון',
              iconData: FluentIcons.arrow_sort_24_regular,
              initialValue: query.sort,
              onSelected: (sort) => _query(query.copyWith(sort: sort)),
              entries: sorts,
            ),
          ),
          AppTopBarItem(
            widget: AppPopupMenuButton<MarkerGroup>(
              tooltip: 'קיבוץ',
              iconData: OtzariaIcons.group_list_24_regular,
              highlighted: query.group != MarkerGroup.none,
              initialValue: query.group,
              onSelected: (group) => _query(query.copyWith(group: group)),
              entries: groups,
            ),
          ),
        ],
        AppTopBarItem(
          widget: BarButton.icon(
            compact: compact,
            tooltip: _selecting ? 'סיום בחירה' : 'בחירה מרובה',
            icon: FluentIcons.multiselect_rtl_24_regular,
            selected: _selecting,
            onPressed: () {
              if (_selecting) {
                _endSelection();
              } else {
                setState(() => _selecting = true);
              }
            },
          ),
        ),
        AppTopBarItem(
          widget: AppPopupMenuButton<_FileAction>(
            tooltip: 'ייצוא, ייבוא ותגיות',
            iconData: FluentIcons.more_horizontal_24_regular,
            onSelected: _onFileAction,
            entries: [
              AppMenuEntry(
                value: _FileAction.print,
                label: state.isSelecting ? 'הדפסת הנבחרים' : 'הדפסת הרשימה',
                icon: FluentIcons.print_24_regular,
              ),
              AppMenuEntry(
                value: _FileAction.word,
                label: state.isSelecting
                    ? 'ייצוא הנבחרים לוורד'
                    : 'ייצוא לוורד',
                icon: OtzariaIcons.document_word_24_regular,
              ),
              AppMenuEntry(
                value: _FileAction.backup,
                label: state.isSelecting
                    ? 'גיבוי הנבחרים'
                    : 'גיבוי כל הסימונים',
                icon: FluentIcons.arrow_download_24_regular,
              ),
              const AppMenuEntry(
                value: _FileAction.importFile,
                label: 'ייבוא מקובץ גיבוי',
                icon: FluentIcons.arrow_upload_24_regular,
              ),
              const AppMenuEntry(
                value: _FileAction.importPlugin,
                label: 'ייבוא מתוסף המרקר הישן',
                icon: FluentIcons.puzzle_piece_24_regular,
              ),
              const AppMenuEntry(
                value: _FileAction.tags,
                label: 'ניהול תגיות',
                icon: FluentIcons.tag_24_regular,
              ),
            ],
          ),
        ),
        AppTopBarItem(
          widget: BarButton.icon(
            compact: compact,
            tooltip: 'הגדרות',
            icon: FluentIcons.settings_24_regular,
            selected: _settingsOpen,
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, MarkerState state) {
    final palette = MarkerSettings.instance.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_legacyCount > 0) _legacyBanner(context),
        if (state.counts.total > 0)
          MarkerFilterBar(
            query: state.query,
            counts: state.counts,
            palette: palette,
            tags: state.tags,
            onChanged: _query,
          ),
        if (_selecting || state.isSelecting)
          _selectionBar(context, state, palette),
        if (state.counts.total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              state.query.hasFilters &&
                      state.counts.matching != state.counts.total
                  ? state.counts.matching == 1
                        ? 'סימון אחד מתוך ${state.counts.total}'
                        : '${state.counts.matching} מתוך ${_count(state.counts.total)}'
                  : _count(state.counts.total),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(child: _list(context, state, palette)),
      ],
    );
  }

  Widget _legacyBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'נמצאו סימונים של תוסף המרקר הישן. אפשר לייבא אותם לכאן — התוסף '
            'ונתוניו לא ישתנו.',
          ),
          if (_legacyPluginEnabled)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'התוסף הישן עדיין פעיל, ומה שיסומן בו מעכשיו לא יגיע לכאן. '
                'אחרי הייבוא מומלץ להשבית אותו. קיצור המקלדת שלו מפעיל עכשיו '
                'את המרקר המובנה.',
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionButton.recommended(
                text: 'ייבוא',
                onPressed: () => _onFileAction(_FileAction.importPlugin),
              ),
              if (_legacyPluginEnabled)
                ActionButton.neutral(
                  text: 'השבתת התוסף הישן',
                  onPressed: _disableLegacyPlugin,
                ),
              ActionButton.ghost(text: 'לא עכשיו', onPressed: _dismissLegacy),
            ],
          ),
        ],
      ),
    );
  }

  /// Ctrl/⌘+A ו-Delete פועלים על הרשימה, אבל לא בתוך שדה טקסט.
  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || isEditableTextFocusTarget()) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyA &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      setState(() => _selecting = true);
      _bloc.add(const MarkerSelectAllToggled());
      return KeyEventResult.handled;
    }
    // Escape שאינו מסיים בחירה נשאר לסגירת החלון או הדיאלוג.
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (_selecting || _bloc.state.isSelecting)) {
      _endSelection();
      return KeyEventResult.handled;
    }
    final ids = _bloc.state.selectedIds;
    if (event.logicalKey == LogicalKeyboardKey.delete && ids.isNotEmpty) {
      unawaited(_deleteSelected(context, ids));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _endSelection() {
    if (!_selecting && !_bloc.state.isSelecting) return;
    _bloc.add(const MarkerSelectionCleared());
    setState(() => _selecting = false);
  }

  Future<void> _deleteSelected(BuildContext context, Set<String> ids) async {
    final confirmed = await confirmMarkerAction(
      context,
      title: 'מחיקת סימונים',
      content: ids.length == 1
          ? 'למחוק את הסימון שנבחר? אפשר לבטל מיד אחרי המחיקה.'
          : 'למחוק ${ids.length} סימונים? אפשר לבטל מיד אחרי המחיקה.',
      confirmText: 'מחיקה',
    );
    if (!confirmed) return;
    await MarkerActions.instance.remove(ids);
    _endSelection();
  }

  Widget _selectionBar(
    BuildContext context,
    MarkerState state,
    MarkerPalette palette,
  ) {
    final ids = state.selectedIds;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(switch (ids.length) {
            0 => 'בחרו סימונים',
            1 => 'נבחר סימון אחד',
            final count => 'נבחרו $count סימונים',
          }),
          ActionButton.ghost(
            text: ids.isNotEmpty && state.items.every((m) => ids.contains(m.id))
                ? 'ביטול הבחירה'
                : 'בחירת כל המוצגים',
            onPressed: () => _bloc.add(const MarkerSelectAllToggled()),
          ),
          if (ids.isNotEmpty) ...[
            AppPopupMenuButton<MarkerColor>(
              tooltip: 'שינוי צבע',
              iconData: FluentIcons.color_24_regular,
              onSelected: (color) => MarkerActions.instance.recolor(ids, color),
              entries: [
                for (final color in palette.menuColors)
                  AppMenuEntry(
                    value: color,
                    label: color.label,
                    icon: FluentIcons.circle_24_filled,
                    iconColor: Color(color.argb),
                  ),
              ],
            ),
            ActionButton.neutral(
              text: 'הוספת תגיות',
              onPressed: () async {
                final tags = await askMarkerTags(context, title: 'הוספת תגיות');
                if (tags != null && tags.isNotEmpty) {
                  await MarkerActions.instance.addTags(ids, tags);
                }
              },
            ),
            ActionButton.warning(
              text: 'מחיקה',
              onPressed: () => _deleteSelected(context, ids),
            ),
          ],
        ],
      ),
    );
  }

  Widget _list(BuildContext context, MarkerState state, MarkerPalette palette) {
    if (state.status == MarkerListStatus.initial ||
        (state.status == MarkerListStatus.loading && state.items.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == MarkerListStatus.failure && state.items.isEmpty) {
      return Center(
        child: ActionButton.neutral(
          text: 'ניסיון נוסף',
          onPressed: () => _bloc.add(MarkerQueryChanged(state.query)),
        ),
      );
    }
    if (state.items.isEmpty) {
      return state.counts.total == 0
          ? const ToolEmptyState(
              icon: FluentIcons.highlight_24_regular,
              message: 'עדיין אין סימונים',
              subtitle:
                  'בחרו טקסט בספר וסמנו אותו מהתפריט (לחיצה ימנית או לחיצה '
                  'ארוכה), מכפתור המרקר שבסרגל או בקיצור המקלדת.',
            )
          : const ToolEmptyState(
              icon: FluentIcons.search_24_regular,
              message: 'לא נמצאו סימונים',
            );
    }
    final rows = _rows(state, palette);
    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: rows.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == rows.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final row = rows[index];
          final mark = row.mark;
          if (mark == null) {
            final dot = row.dot;
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
              child: Row(
                children: [
                  if (dot != null) ...[
                    Icon(FluentIcons.circle_16_filled, size: 14, color: dot),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      row.header!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            );
          }
          return MarkerTile(
            key: ValueKey(mark.id),
            mark: mark,
            palette: palette,
            selecting: _selecting || state.isSelecting,
            selected: state.selectedIds.contains(mark.id),
            focused: mark.id == _focusedId,
            onToggleSelected: (id) {
              if (!_selecting) setState(() => _selecting = true);
              _bloc.add(MarkerSelectionToggled(id));
            },
          );
        },
      ),
    );
  }

  /// הרשימה עם כותרת לכל קבוצה. הקבוצות רציפות כי הקיבוץ הוא מפתח המיון.
  /// [dot] — צבע הקבוצה, בקיבוץ לפי צבע.
  List<({String? header, Color? dot, MarkerHighlight? mark})> _rows(
    MarkerState state,
    MarkerPalette palette,
  ) {
    String? keyOf(MarkerHighlight mark) => switch (state.query.group) {
      MarkerGroup.none => null,
      MarkerGroup.book => markerBookLabel(mark.bookTitle, pdf: mark.pdf),
      MarkerGroup.color =>
        palette.colorById(mark.colorId)?.label ?? 'צבע שנמחק',
      MarkerGroup.date => markerDateLabel(mark.createdAt),
    };
    final rows = <({String? header, Color? dot, MarkerHighlight? mark})>[];
    String? previous;
    for (final mark in state.items) {
      final key = keyOf(mark);
      if (key != null && key != previous) {
        final color = state.query.group == MarkerGroup.color
            ? Color(
                palette.colorById(mark.colorId)?.argb ??
                    MarkerColor.argbOf(mark.colorHex),
              )
            : null;
        rows.add((header: key, dot: color, mark: null));
        previous = key;
      }
      rows.add((header: null, dot: null, mark: mark));
    }
    return rows;
  }
}

String _count(int count) => count == 1 ? 'סימון אחד' : '$count סימונים';
