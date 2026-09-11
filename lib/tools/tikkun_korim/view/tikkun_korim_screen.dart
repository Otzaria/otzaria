/// המסך של הכלי "תיקון קוראים".
library;

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/app_colors.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_export_dialog.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_dependencies.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/tikkun_settings_panel.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/printing/safer_print_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// רוחב בורר בסרגל העליון והריפוד משני צדדיו.
const double _kSelectorWidth = 150;
const double _kSelectorPadding = 2;

/// רוחב חלונית ההגדרות — כמו בשאר הכלים.
const double _kSettingsPanelWidth = 400;

class TikkunKorimScreen extends StatelessWidget {
  final TikkunEngine? engine;
  final TikkunDataSource? data;
  final TikkunKorimRepository? repository;

  const TikkunKorimScreen({
    super.key,
    this.engine,
    this.data,
    this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final engine = this.engine ?? TikkunDependencies.engine;
    final data = this.data ?? TikkunDependencies.data;
    if (engine == null || data == null) {
      return const ToolEmptyState(
        icon: FluentIcons.book_open_24_regular,
        message: ToolsMessages.tikkunNoData,
      );
    }
    return BlocProvider(
      create: (_) => TikkunKorimBloc(
        repository:
            repository ?? TikkunKorimRepository(engine: engine, data: data),
        data: data,
      )..add(const TikkunStarted()),
      child: TikkunKorimView(data: data),
    );
  }
}

class TikkunKorimView extends StatefulWidget {
  final TikkunDataSource data;

  const TikkunKorimView({super.key, required this.data});

  @override
  State<TikkunKorimView> createState() => _TikkunKorimViewState();
}

class _TikkunKorimViewState extends State<TikkunKorimView> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'tikkun_korim_shortcuts',
    skipTraversal: true,
  );
  bool _settingsOpen = false;
  int _handledScrollRequest = 0;
  int _lastReportedLine = -1;
  Timer? _syncTimer;

  /// התקדמות הייצוא — (הדף הנוכחי, סך הדפים); `null` כשאין ייצוא פעיל.
  final ValueNotifier<(int, int)?> _exportProgress = ValueNotifier(null);
  TikkunPdfExporter? _activeExport;

  /// שם הפעולה הרצה, לחלונית ההתקדמות — "ייצוא" או "הדפסה".
  String _progressLabel = 'ייצוא';

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositionsChanged);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositionsChanged);
    _keyboardFocusNode.dispose();
    _syncTimer?.cancel();
    // סגירת הטאב באמצע ייצוא — הייצוא נעצר בשקט.
    _activeExport?.cancel();
    _exportProgress.dispose();
    super.dispose();
  }

  /// סנכרון בוררי הסרגל למיקום הגלילה, בקצב נמוך.
  void _onPositionsChanged() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions
        .where((p) => p.itemTrailingEdge > 0)
        .fold<int?>(
          null,
          (min, p) => min == null || p.index < min ? p.index : min,
        );
    if (first == null || first == _lastReportedLine) return;
    _lastReportedLine = first;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      context.read<TikkunKorimBloc>().add(TikkunVisibleLineChanged(first));
    });
  }

  void _handleScrollRequest(TikkunKorimState state) {
    if (state.scrollRequestId == _handledScrollRequest) return;
    final line = state.scrollToLine;
    _handledScrollRequest = state.scrollRequestId;
    if (line == null || !_scrollController.isAttached) return;
    _lastReportedLine = line;
    // רשימה חדשה נפתחת בראשה ממילא; scrollTo לשורה 0 מיישר אותה לקצה
    // הצג מעל הריפוד העליון, ומזיז את העמוד ברבע שנייה בכל מעבר.
    if (line == 0) return;
    _scrollController.scrollTo(
      index: line.clamp(0, (state.currentLines.length - 1).clamp(0, 1 << 30)),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ── ייצוא ל-PDF והדפסה ─────────────────────────────────────────────────

  /// מייצא ל-PDF, או — עם [print] — שולח את אותו PDF להדפסה.
  Future<void> _export(
    BuildContext context,
    TikkunKorimState state, {
    bool print = false,
  }) async {
    final allColumns = [for (final page in state.pages) page.lines];
    // בתורה העמודים מכסים את כל החומשים — "הכל" וטווח הפסוקים מוגבלים
    // לחומש הנוכחי, כמו בתוסף.
    final bookColumns = _currentBookColumns(state, allColumns);
    // "עמודים מקוריים" קיים רק כשהטורים הם עמודי שיטה בני 42/51 שורות.
    final hasOriginalPages =
        state.nav.section == TikkunSection.torah &&
        state.nav.methodId != 'single_page';
    // טווח פסוקים — רק בספר שלם; בהפטרה ובקריאת מועד הפרקים אינם רצופים.
    final hasVerseRange =
        state.nav.section == TikkunSection.torah ||
        state.nav.section.isTanachBook;
    final options = await showTikkunExportDialog(
      context: context,
      columnCount: state.columnCount,
      currentColumn: state.nav.currentColumnIndex,
      allowOriginalPages: hasOriginalPages,
      verseDomain: hasVerseRange ? tikkunVerseDomain(bookColumns) : null,
      title: print ? 'הדפסה' : 'ייצוא ל-PDF',
      confirmText: print ? 'הדפס' : 'ייצא',
    );
    if (options == null || !mounted) return;

    final wholeBook =
        options.scope == TikkunExportScope.all ||
        options.scope == TikkunExportScope.verseRange;
    final columns = selectTikkunExportColumns(
      wholeBook ? bookColumns : allColumns,
      options,
      state.nav.currentColumnIndex,
    );
    if (columns.every((column) => column.isEmpty)) {
      UiSnack.showError(ToolsMessages.tikkunExportNoContent);
      return;
    }

    _progressLabel = print ? 'הדפסה' : 'ייצוא';
    _exportProgress.value = (0, 0);
    final exporter = TikkunPdfExporter(
      settings: state.settings,
      options: options,
      headerTitle: state.headerTitle,
      headerSubtitle: state.headerSubtitle,
    );
    _activeExport = exporter;
    try {
      final Uint8List bytes = await exporter.export(
        columns,
        onProgress: (done, total) {
          if (mounted) _exportProgress.value = (done, total);
        },
      );
      if (!mounted) return;
      final name = _exportFileName(state, options);
      if (print) {
        await printPdfWithSaferMode(
          name: name,
          onLayout: (_) => bytes,
          // ה-PDF כבר מעומד; אין מה לפרוס מחדש לפי המדפסת.
          dynamicLayout: false,
          usePrinterSettings: true,
        );
        return;
      }
      final path = await saveFileWithExtension(
        dialogTitle: 'ייצוא ל-PDF',
        fileName: '$name.pdf',
        extension: 'pdf',
        bytes: bytes,
      );
      if (path == null) return;
      UiSnack.showSuccess(ToolsMessages.tikkunExportSaved(path));
    } on TikkunExportCancelled {
      // ביטול מכוון — אין מה להודיע.
    } catch (error) {
      if (!mounted) return;
      UiSnack.showError(
        print
            ? ToolsMessages.tikkunPrintFailed(error)
            : ToolsMessages.tikkunExportFailed(error),
      );
    } finally {
      _activeExport = null;
      if (mounted) _exportProgress.value = null;
    }
  }

  List<List<TikkunLine>> _currentBookColumns(
    TikkunKorimState state,
    List<List<TikkunLine>> allColumns,
  ) {
    if (state.nav.section != TikkunSection.torah) return allColumns;
    final books = widget.data.chumashim;
    final index = books.indexWhere((b) => b.id == state.nav.bookId);
    if (index < 0 || books[index].parashot.isEmpty) return allColumns;
    final next = index + 1 < books.length ? books[index + 1] : null;
    return sliceTikkunBookColumns(
      allColumns,
      firstParasha: books[index].parashot.first,
      nextBookFirstParasha: next == null || next.parashot.isEmpty
          ? null
          : next.parashot.first,
    );
  }

  String _exportFileName(TikkunKorimState state, TikkunExportOptions options) {
    var title = (state.headerTitle ?? _currentBookTitle(state)).trim();
    if (options.scope == TikkunExportScope.verseRange) {
      title +=
          ' ${toHebrewNumeral(options.fromChapter)},'
          '${toHebrewNumeral(options.fromVerse)} - '
          '${toHebrewNumeral(options.toChapter)},'
          '${toHebrewNumeral(options.toVerse)}';
    }
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return sanitized.isEmpty ? 'תיקון קוראים' : sanitized;
  }

  String _currentBookTitle(TikkunKorimState state) {
    if (state.nav.section != TikkunSection.torah) return 'תיקון קוראים';
    for (final book in widget.data.chumashim) {
      if (book.id == state.nav.bookId) return 'תיקון קוראים ${book.name}';
    }
    return 'תיקון קוראים';
  }

  Widget _exportOverlay() => ValueListenableBuilder<(int, int)?>(
    valueListenable: _exportProgress,
    builder: (context, progress, _) {
      if (progress == null) return const SizedBox.shrink();
      final (done, total) = progress;
      return Positioned.fill(
        child: ColoredBox(
          color: AppColors.dialogBarrier,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 240,
                      child: LinearProgressIndicator(
                        value: total == 0 ? null : done / total,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      total == 0
                          ? 'מכין את ה$_progressLabel…'
                          : 'מעבד עמוד $done מתוך $total',
                    ),
                    const SizedBox(height: 12),
                    ActionButton.ghost(
                      text: 'ביטול',
                      onPressed: () => _activeExport?.cancel(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TikkunKorimBloc, TikkunKorimState>(
      listener: (context, state) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _handleScrollRequest(state),
        );
      },
      builder: (context, state) {
        return CallbackShortcuts(
          bindings: _keyBindings(
            context,
            context.watch<SettingsBloc>().state.shortcuts,
          ),
          child: Focus(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            child: _buildScaffold(context, state),
          ),
        );
      },
    );
  }

  /// קיצורי המסך: דפדוף העמודים (ניתן לשינוי בהגדרות) והחיצים ב-RTL,
  /// ו-Escape לסגירת חלונית ההגדרות.
  Map<ShortcutActivator, VoidCallback> _keyBindings(
    BuildContext context,
    Map<String, String> shortcuts,
  ) {
    void turnPage({required bool next}) {
      if (_isEditing()) return;
      context.read<TikkunKorimBloc>().add(
        next ? const TikkunNextColumn() : const TikkunPrevColumn(),
      );
    }

    final bindings = <ShortcutActivator, VoidCallback>{};
    void register(String key, String fallback, VoidCallback callback) {
      final activator = ShortcutHelper.activatorFromShortcut(
        shortcuts[key] ?? fallback,
        mapCtrlToMeta: false,
      );
      if (activator != null) bindings[activator] = callback;
    }

    register(
      ShortcutValidator.tikkunNextPageKey,
      'ctrl+pagedown',
      () => turnPage(next: true),
    );
    register(
      ShortcutValidator.tikkunPrevPageKey,
      'ctrl+pageup',
      () => turnPage(next: false),
    );
    // RTL: חץ שמאל מקדם עמוד, חץ ימין חוזר.
    bindings[const SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      control: true,
    )] = () =>
        turnPage(next: true);
    bindings[const SingleActivator(
      LogicalKeyboardKey.arrowRight,
      control: true,
    )] = () =>
        turnPage(next: false);
    if (_settingsOpen) {
      bindings[const SingleActivator(LogicalKeyboardKey.escape)] =
          _closeSettings;
    }
    return bindings;
  }

  /// קיצור פועל רק כשהמוקד אינו בשדה טקסט (שדה קפיצה לעמוד, חיפוש בבורר).
  bool _isEditing() {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  Widget _buildScaffold(BuildContext context, TikkunKorimState state) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < kTikkunTwoColumnMinWidth;
          final columns = _columnsFor(state, narrow);
          return Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(
                    context,
                    state,
                    columns,
                    constraints.maxWidth,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _buildReader(context, state, columns),
                        ),
                        _buildSettingsPanel(context, state),
                      ],
                    ),
                  ),
                ],
              ),
              _exportOverlay(),
            ],
          );
        },
      ),
    );
  }

  void _closeSettings() => setState(() => _settingsOpen = false);

  /// הטורים המוצגים בפועל. במסך צר מדי לשני טורים מוצג טור אחד —
  /// המנוקד כברירת מחדל, ולחצן ההחלפה מציג את הסת"ם במקומו.
  _TikkunColumns _columnsFor(TikkunKorimState state, bool narrow) {
    final settings = state.settings;
    if (narrow && !settings.isSingleColumn) {
      final forced = settings.copyWith(
        hideStam: !state.peekSecondColumn,
        hideNikud: state.peekSecondColumn,
        centerSingleColumn: true,
      );
      return _TikkunColumns(
        settings: forced,
        hideStam: forced.hideStam,
        hideNikud: forced.hideNikud,
        canSwap: true,
      );
    }
    return _TikkunColumns(
      settings: settings,
      hideStam: state.effectiveHideStam,
      hideNikud: state.effectiveHideNikud,
      canSwap: settings.isSingleColumn,
    );
  }

  /// חלונית ההגדרות — צפה מעל התוכן, בצד שבו יושב כפתור ההגדרות (trailing).
  Widget _buildSettingsPanel(BuildContext context, TikkunKorimState state) {
    return ContextOverlayPanel(
      isOpen: _settingsOpen,
      onClose: _closeSettings,
      width: _kSettingsPanelWidth,
      title: 'הגדרות',
      scrollable: true,
      child: TikkunSettingsPanel(
        settings: state.settings,
        onChanged: (settings) => context.read<TikkunKorimBloc>().add(
          TikkunSettingsUpdated(settings),
        ),
      ),
    );
  }

  // ── הסרגל העליון ───────────────────────────────────────────────────────

  Widget _buildTopBar(
    BuildContext context,
    TikkunKorimState state,
    _TikkunColumns columns,
    double availableWidth,
  ) {
    final bloc = context.read<TikkunKorimBloc>();
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    final nav = state.nav;
    final selectors = <Widget>[
      _selector<TikkunSection>(
        value: nav.section,
        entries: [
          for (final section in TikkunSection.values)
            AppMenuEntry(value: section, label: section.label),
        ],
        onSelected: (value) =>
            bloc.add(TikkunSectionChanged(value ?? TikkunSection.torah)),
      ),
      if (nav.section == TikkunSection.torah)
        _selector<String>(
          value: nav.methodId,
          entries: [
            for (final method in widget.data.methods)
              AppMenuEntry(value: method.id, label: method.name),
            const AppMenuEntry(
              value: 'single_page',
              label: 'עמוד אחד ארוך',
            ),
          ],
          onSelected: (value) =>
              value == null ? null : bloc.add(TikkunMethodChanged(value)),
        ),
      if (nav.section == TikkunSection.torah)
        _selector<String>(
          value: nav.bookId,
          entries: [
            for (final book in widget.data.chumashim)
              AppMenuEntry(value: book.id, label: book.name),
          ],
          onSelected: (value) =>
              value == null ? null : bloc.add(TikkunBookChanged(value)),
        ),
      if (nav.section == TikkunSection.torah) _parashaSelector(bloc, state),
      if (nav.section == TikkunSection.torah) _aliyaSelector(bloc, state),
      if (nav.section.isTanachBook) _tanachBookSelector(bloc, state),
      if (nav.section.isTanachBook) _chapterSelector(bloc, state),
      if (nav.section == TikkunSection.haftarot) _haftarahSelector(bloc, state),
      if (nav.section == TikkunSection.torahReadings)
        _readingSelector(bloc, state),
    ];

    final pageNav = state.columnCount > 1
        ? [
            IconButton(
              tooltip: 'עמוד קודם',
              icon: const RtlIcon(FluentIcons.chevron_right_24_regular),
              onPressed: state.nav.currentColumnIndex > 0
                  ? () => bloc.add(const TikkunPrevColumn())
                  : null,
            ),
            SizedBox(
              width: _kSelectorWidth,
              child: _PageIndicator(state: state),
            ),
            IconButton(
              tooltip: 'עמוד הבא',
              icon: const RtlIcon(FluentIcons.chevron_left_24_regular),
              onPressed: state.nav.currentColumnIndex < state.columnCount - 1
                  ? () => bloc.add(const TikkunNextColumn())
                  : null,
            ),
          ]
        : const <Widget>[];

    // הבוררים גמישים ומתכווצים כשאין מקום; פריטי הסיום קבועים, ולכן
    // הסרגל מקבל את רוחבם כדי שהבוררים לא יגלשו מתחתיהם.
    double trailingWidthFor(int buttons, {required bool withPageNav}) {
      final count = buttons + (withPageNav ? 2 : 0);
      return count * kMinInteractiveDimension +
          (withPageNav ? _kSelectorWidth : 0) +
          AppTopBar.itemSpacing(isCompact) * count;
    }

    final buttons = (columns.canSwap ? 1 : 0) + 3;
    // כשהבוררים ייאלצו להתכווץ מתחת לרוחבם המלא הטקסט שבהם נקטע — אז הם
    // עוברים, יחד עם ניווט העמודים, לשורה שנייה משלהם.
    final selectorsWidth =
        selectors.length * (_kSelectorWidth + 2 * _kSelectorPadding);
    final sidePadding = 2 * AppTopBar.horizontalPadding(isCompact);
    final fullTrailing = trailingWidthFor(
      buttons,
      withPageNav: pageNav.isNotEmpty,
    );
    final twoRows =
        selectorsWidth + fullTrailing + sidePadding > availableWidth;
    // ניווט העמודים נשאר ליד הלחצנים כל עוד יש לו מקום שם.
    final pageNavInBar =
        pageNav.isNotEmpty &&
        (!twoRows || fullTrailing + sidePadding <= availableWidth);
    return AppTopBar(
      minTrailingWidth: trailingWidthFor(buttons, withPageNav: pageNavInBar),
      leadingItems: [
        if (!twoRows)
          for (final selector in selectors)
            AppTopBarItem(widget: selector, flexible: true),
      ],
      secondaryRow: twoRows
          ? _selectorsRow(
              selectors,
              pageNavInBar ? const [] : pageNav,
              isCompact,
            )
          : null,
      trailingItems: [
        if (pageNavInBar)
          for (final item in pageNav) AppTopBarItem(widget: item),
        if (columns.canSwap)
          AppTopBarItem(
            widget: IconButton(
              tooltip: state.peekSecondColumn
                  ? 'חזור לטור הראשי'
                  : 'הצג טור שני',
              isSelected: state.peekSecondColumn,
              icon: const Icon(FluentIcons.arrow_swap_24_regular),
              onPressed: () => bloc.add(const TikkunPeekToggled()),
            ),
          ),
        AppTopBarItem(
          dividerBefore: true,
          widget: IconButton(
            tooltip: 'הדפסה',
            icon: const Icon(FluentIcons.print_24_regular),
            onPressed: state.pages.isEmpty
                ? null
                : () => _export(context, state, print: true),
          ),
        ),
        AppTopBarItem(
          widget: IconButton(
            tooltip: 'ייצוא ל-PDF',
            icon: const Icon(FluentIcons.document_pdf_24_regular),
            onPressed: state.pages.isEmpty
                ? null
                : () => _export(context, state),
          ),
        ),
        AppTopBarItem(
          widget: IconButton(
            tooltip: 'הגדרות',
            isSelected: _settingsOpen,
            icon: const Icon(FluentIcons.settings_24_regular),
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          ),
        ),
      ],
    );
  }

  /// הבוררים וניווט העמודים במסך צר — ברוחבם המלא, נשברים לכמה שורות.
  Widget _selectorsRow(
    List<Widget> selectors,
    List<Widget> pageNav,
    bool isCompact,
  ) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppTopBar.horizontalPadding(isCompact),
      vertical: 4,
    ),
    child: Wrap(
      runSpacing: 4,
      children: [
        for (final selector in selectors)
          SizedBox(
            width: _kSelectorWidth + 2 * _kSelectorPadding,
            child: selector,
          ),
        if (pageNav.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: pageNav),
      ],
    ),
  );

  Widget _selector<T>({
    required T? value,
    required List<AppMenuEntry<T>> entries,
    required ValueChanged<T?> onSelected,
    bool enableSearch = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _kSelectorPadding),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kSelectorWidth),
      child: AppDropdownField<T>(
        value: value,
        entries: entries,
        enableSearch: enableSearch,
        onSelected: onSelected,
      ),
    ),
  );

  Widget _parashaSelector(TikkunKorimBloc bloc, TikkunKorimState state) {
    final book = widget.data.chumashim.firstWhere(
      (b) => b.id == state.nav.bookId,
      orElse: () => widget.data.chumashim.first,
    );
    return _selector<String>(
      value: book.parashot.contains(state.nav.parashaName)
          ? state.nav.parashaName
          : (book.parashot.isEmpty ? null : book.parashot.first),
      entries: [
        for (final parasha in book.parashot)
          AppMenuEntry(value: parasha, label: parasha),
      ],
      onSelected: (value) =>
          value == null ? null : bloc.add(TikkunParashaChanged(value)),
    );
  }

  Widget _aliyaSelector(TikkunKorimBloc bloc, TikkunKorimState state) {
    final book = widget.data.chumashim.firstWhere(
      (b) => b.id == state.nav.bookId,
      orElse: () => widget.data.chumashim.first,
    );
    final aliyot = widget.data.aliyotOf(book.name, state.nav.parashaName);
    return _selector<int>(
      value: state.aliyaIdx ?? -1,
      entries: [
        const AppMenuEntry(value: -1, label: 'כל הפרשה'),
        for (var i = 0; i < aliyot.length; i++)
          AppMenuEntry(
            value: i,
            label: widget.data.aliyaDisplayName(aliyot[i].aliya),
          ),
      ],
      onSelected: (value) => bloc.add(
        TikkunAliyaSelected(value == null || value < 0 ? null : value),
      ),
    );
  }

  Widget _tanachBookSelector(TikkunKorimBloc bloc, TikkunKorimState state) {
    final books = widget.data.booksOfSection(state.nav.section);
    return _selector<String>(
      value: books.any((b) => b.id == state.nav.tanachBookId)
          ? state.nav.tanachBookId
          : (books.isEmpty ? null : books.first.id),
      enableSearch: true,
      entries: [
        for (final book in books)
          AppMenuEntry(value: book.id, label: book.name),
      ],
      onSelected: (value) =>
          value == null ? null : bloc.add(TikkunBookChanged(value)),
    );
  }

  Widget _chapterSelector(TikkunKorimBloc bloc, TikkunKorimState state) {
    final books = widget.data.booksOfSection(state.nav.section);
    final book = books.isEmpty
        ? null
        : books.firstWhere(
            (b) => b.id == state.nav.tanachBookId,
            orElse: () => books.first,
          );
    final chapters = book?.chapters ?? 0;
    return _selector<int>(
      value: state.nav.tanachChapter.clamp(1, chapters == 0 ? 1 : chapters),
      enableSearch: true,
      entries: [
        for (var i = 1; i <= chapters; i++)
          AppMenuEntry(value: i, label: 'פרק ${toHebrewNumeral(i)}'),
      ],
      onSelected: (value) =>
          value == null ? null : bloc.add(TikkunChapterSelected(value)),
    );
  }

  Widget _haftarahSelector(TikkunKorimBloc bloc, TikkunKorimState state) {
    final list = bloc.haftarotForCurrentLand();
    return _selector<String>(
      value: list.any((h) => h.id == state.nav.haftarahId)
          ? state.nav.haftarahId
          : (list.isEmpty ? null : list.first.id),
      enableSearch: true,
      entries: [
        for (final haftarah in list)
          AppMenuEntry(
            value: haftarah.id,
            label: haftarah.name,
            subtitle: haftarah.category == 'parasha'
                ? 'הפטרות פרשיות'
                : 'שבתות מיוחדות וחגים',
          ),
      ],
      onSelected: (value) =>
          value == null ? null : bloc.add(TikkunHaftarahChanged(value)),
    );
  }

  Widget _readingSelector(TikkunKorimBloc bloc, TikkunKorimState state) {
    final list = bloc.readingsForCurrentLand();
    final categories = widget.data.readingCategoryNames;
    return _selector<String>(
      value: list.any((r) => r.id == state.nav.torahReadingId)
          ? state.nav.torahReadingId
          : (list.isEmpty ? null : list.first.id),
      enableSearch: true,
      entries: [
        for (final reading in list)
          AppMenuEntry(
            value: reading.id,
            label: reading.name,
            subtitle: categories[reading.category] ?? reading.category,
          ),
      ],
      onSelected: (value) =>
          value == null ? null : bloc.add(TikkunReadingChanged(value)),
    );
  }

  // ── אזור הקריאה ────────────────────────────────────────────────────────

  Widget _buildReader(
    BuildContext context,
    TikkunKorimState state,
    _TikkunColumns columns,
  ) {
    if (state.error != null) {
      return ToolEmptyState(
        icon: FluentIcons.error_circle_24_regular,
        message: state.error!,
      );
    }
    if (state.isLoading && state.pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final lines = state.currentLines;
    if (lines.isEmpty) {
      // ה-BLoC מנסח הודעה מדויקת (למשל "אין הפטרה במנהג זה"); בלעדיה נופלים
      // להודעה הגנרית.
      return ToolEmptyState(
        icon: FluentIcons.book_open_24_regular,
        message: state.headerSubtitle ?? ToolsMessages.tikkunNoData,
      );
    }
    return ReaderPage(
      key: ValueKey(
        'tikkun-page-${state.nav.currentColumnIndex}-'
        '${identityHashCode(lines)}',
      ),
      lines: lines,
      settings: columns.settings,
      hideStam: columns.hideStam,
      hideNikud: columns.hideNikud,
      headerTitle: state.headerTitle,
      headerSubtitle: state.headerSubtitle,
      scrollController: _scrollController,
      positionsListener: _positions,
    );
  }
}

/// מחוון העמוד — לחיצה פותחת דילוג לעמוד מסוים.
/// אילו טורים מוצגים ואם יש לחצן החלפה ביניהם.
class _TikkunColumns {
  final TikkunSettings settings;
  final bool hideStam;
  final bool hideNikud;
  final bool canSwap;

  const _TikkunColumns({
    required this.settings,
    required this.hideStam,
    required this.hideNikud,
    required this.canSwap,
  });
}

class _PageIndicator extends StatefulWidget {
  final TikkunKorimState state;

  const _PageIndicator({required this.state});

  @override
  State<_PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<_PageIndicator> {
  final MenuController _menu = MenuController();
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _jump() {
    final total = widget.state.columnCount;
    if (total == 0) return;
    final page = int.tryParse(_input.text.trim());
    if (page == null) return;
    _menu.close();
    context.read<TikkunKorimBloc>().add(TikkunColumnSelected(page - 1));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.state.columnCount;
    final current = widget.state.nav.currentColumnIndex + 1;
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 220,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'דילוג לעמוד',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RtlTextField(
                        controller: _input,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(isDense: true),
                        onSubmitted: (_) => _jump(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ActionButton.recommended(text: 'עבור', onPressed: _jump),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  total > 0 ? 'מתוך $total עמודים' : '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => ActionButton.ghost(
        text: total == 0 ? 'טוען...' : 'עמוד $current מתוך $total',
        onPressed: total == 0
            ? null
            : () {
                _input.text = '$current';
                controller.isOpen ? controller.close() : controller.open();
              },
      ),
    );
  }
}
