import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biographies_credit_line.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';
import 'package:otzaria/tools/tool_query.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:otzaria/widgets/layout/tool_results_header.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

class BiographiesScreen extends StatefulWidget {
  const BiographiesScreen({super.key, this.repository, this.queryInbox});

  final BiographiesRepository? repository;
  final ToolQueryInbox? queryInbox;

  @override
  State<BiographiesScreen> createState() => _BiographiesScreenState();
}

class _BiographiesScreenState extends State<BiographiesScreen>
    with ToolQueryConsumer {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final BiographiesRepository _repository =
      widget.repository ?? BiographiesRepository.instance;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _eraScroll = ScrollController();
  BiographiesBundle? _bundle;
  Map<String, Biography> _byId = const {};
  List<Biography> _filteredResults = [];
  String? _era;
  bool _isLoading = true;
  bool _loadFailed = false;

  /// Entries opened through links, the last one shown over the list.
  final List<Biography> _opened = [];

  List<Biography> get _allBiographies => _bundle?.entries ?? const [];

  @override
  ToolQueryInbox? get toolQueryInbox => widget.queryInbox;

  @override
  bool get canApplyToolQuery => !_isLoading;

  @override
  void applyToolQuery(ToolQuery query) {
    fillSearchField(_searchController, query.text);
    _performSearch(query.text);
  }

  @override
  void initState() {
    super.initState();
    _loadBiographies();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _eraScroll.dispose();
    super.dispose();
  }

  Future<void> _loadBiographies() async {
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    try {
      final bundle = await _repository.loadBundle();
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _byId = {for (final bio in bundle.entries) bio.id: bio};
        _filteredResults = bundle.entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
      UiSnack.showError(ToolsMessages.biographiesLoadError(e));
    }
    consumeToolQuery();
  }

  void _performSearch(String query) {
    final inEra = _era == null
        ? _allBiographies
        : _allBiographies.where((bio) => bio.era == _era).toList();
    setState(() {
      _opened.clear();
      _filteredResults = BiographiesRepository.filter(inEra, query);
    });
  }

  void _resetFilters() {
    _searchController.clear();
    _era = null;
    _performSearch('');
  }

  void _selectEra(String? era) {
    _era = era;
    _performSearch(_searchController.text);
  }

  void _openEntry(String id) {
    final bio = _byId[id];
    if (bio != null) setState(() => _opened.add(bio));
  }

  void _closeEntry() => setState(_opened.removeLast);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingIndicator();
    }

    return CallbackShortcuts(
      bindings: {
        currentWindowSearchActivator(context): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: Column(
        children: [
          AppTopBar(
            center: OtzariaSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: 'חפש רב לפי שם או כינוי...',
              icon: OtzariaIcons.search_in_person_24_regular,
              autofocus: true,
              onChanged: _performSearch,
              onClear: () => _performSearch(''),
            ),
          ),
          if (_bundle case final bundle? when bundle.entries.isNotEmpty)
            _buildEraChips(bundle),
          Expanded(
            child: ToolPanelWrapper(
              child: Column(
                children: [
                  if ((_bundle?.entries.isNotEmpty ?? false) && _opened.isEmpty)
                    ToolResultsHeader(
                      label: _filteredResults.length == 1
                          ? 'ערך אחד'
                          : '${_filteredResults.length} ערכים',
                    ),
                  Expanded(
                    // The list stays mounted under an opened entry, so going
                    // back keeps its scroll position.
                    child: Stack(
                      children: [
                        Offstage(
                          offstage: _opened.isNotEmpty,
                          child: _buildResultsList(),
                        ),
                        if (_opened.isNotEmpty) _buildOpenedEntry(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_bundle case final bundle? when bundle.entries.isNotEmpty)
            BiographiesCreditLine(bundle: bundle),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_loadFailed) {
      return OtzariaErrorState(
        title: 'טעינת הביוגרפיות נכשלה',
        actions: [
          ActionButton.recommended(
            text: 'נסה שוב',
            icon: FluentIcons.arrow_clockwise_24_regular,
            onPressed: _loadBiographies,
          ),
        ],
      );
    }

    if (_allBiographies.isEmpty) {
      return const ToolEmptyState(
        icon: OtzariaIcons.person_24_regular,
        message: 'נתוני הביוגרפיות אינם זמינים',
      );
    }

    if (_filteredResults.isEmpty) return _buildNoResults();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMD,
        AppTokens.spaceXS,
        AppTokens.spaceMD,
        AppTokens.spaceMD,
      ),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        final bio = _filteredResults[index];
        return BiographyCard(
          key: ValueKey(bio.id),
          biography: bio,
          canOpen: _byId.containsKey,
          onOpen: _openEntry,
        );
      },
    );
  }

  Widget _buildOpenedEntry() {
    final bio = _opened.last;
    final previous = _opened.length > 1 ? _opened[_opened.length - 2] : null;
    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.ghost(
            text: previous == null ? 'חזרה לרשימה' : 'חזרה אל ${previous.name}',
            iconWidget: const RtlIcon(FluentIcons.arrow_left_24_regular),
            onPressed: _closeEntry,
          ),
        ),
        const SizedBox(height: AppTokens.spaceXS),
        BiographyCard(
          key: ValueKey('opened-${_opened.length}-${bio.id}'),
          biography: bio,
          canOpen: _byId.containsKey,
          onOpen: _openEntry,
          initiallyExpanded: true,
        ),
      ],
    );
  }

  Widget _buildNoResults() {
    final query = _searchController.text.trim();
    final eraLabel = _era == null
        ? null
        : _bundle?.eras.where((e) => e.key == _era).firstOrNull?.label;
    if (query.isEmpty && eraLabel == null) {
      return const ToolEmptyState(
        icon: OtzariaIcons.person_24_regular,
        message: 'לא נמצאו תוצאות',
      );
    }
    final both = query.isNotEmpty && eraLabel != null;
    final message = [
      query.isEmpty ? 'אין ערכים' : 'אין ערכים שמתאימים לחיפוש "$query"',
      if (eraLabel != null) 'בתקופת "$eraLabel"',
    ].join(' ');
    return OtzariaEmptyState(
      icon: OtzariaIcons.person_24_regular,
      title: 'לא נמצאו תוצאות',
      message: '$message.',
      actions: [
        if (both)
          ActionButton.neutral(
            text: 'חיפוש בכל התקופות',
            onPressed: () => _selectEra(null),
          ),
        ActionButton.recommended(
          text: both
              ? 'איפוס החיפוש והמסננים'
              : query.isNotEmpty
              ? 'ניקוי החיפוש'
              : 'הצגת כל התקופות',
          icon: FluentIcons.arrow_reset_24_regular,
          onPressed: _resetFilters,
        ),
      ],
    );
  }

  /// One row of era chips across the window, scrolled sideways with the
  /// wheel or by dragging when they do not all fit.
  Widget _buildEraChips(BiographiesBundle bundle) {
    Widget chip(String label, String? era) => Padding(
      padding: const EdgeInsetsDirectional.only(end: AppTokens.spaceSM),
      child: ChoiceChip(
        label: Text(label),
        selected: _era == era,
        onSelected: (_) => _selectEra(era),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && _eraScroll.hasClients) {
          final position = _eraScroll.position;
          _eraScroll.jumpTo(
            (position.pixels + event.scrollDelta.dy).clamp(
              0.0,
              position.maxScrollExtent,
            ),
          );
        }
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
          scrollbars: false,
        ),
        child: SingleChildScrollView(
          controller: _eraScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppTokens.spaceMD,
            AppTokens.spaceSM,
            AppTokens.spaceSM,
            AppTokens.spaceXS,
          ),
          child: Row(
            children: [
              chip('הכל', null),
              for (final era in bundle.presentEras) chip(era.label, era.key),
            ],
          ),
        ),
      ),
    );
  }
}
