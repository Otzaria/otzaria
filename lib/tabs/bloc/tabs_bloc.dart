import 'dart:async';
import 'dart:math';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository _repository;

  void _disposeTabLater(OpenedTab tab) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        tab.dispose();
      }),
    );
  }

  TabsBloc({
    required TabsRepository repository,
  })  : _repository = repository,
        super(TabsState.initial()) {
    on<LoadTabs>(_onLoadTabs);
    on<ReplaceAllTabs>(_onReplaceAllTabs, transformer: sequential());
    on<AddTab>(_onAddTab, transformer: sequential());
    on<OpenOrFocusTab>(_onOpenOrFocusTab, transformer: sequential());
    on<RemoveTab>(_onRemoveTab, transformer: sequential());
    on<SetCurrentTab>(_onSetCurrentTab, transformer: sequential());
    on<CloseAllTabs>(_onCloseAllTabs, transformer: sequential());
    on<CloseOtherTabs>(_onCloseOtherTabs, transformer: sequential());
    on<CloneTab>(_onCloneTab);
    on<MoveTab>(_onMoveTab, transformer: sequential());
    on<NavigateToNextTab>(_onNavigateToNextTab, transformer: sequential());
    on<NavigateToPreviousTab>(_onNavigateToPreviousTab,
        transformer: sequential());
    on<CloseCurrentTab>(_onCloseCurrentTab);
    on<SaveTabs>(_onSaveTabs, transformer: sequential());
    on<TogglePinTab>(_onTogglePinTab, transformer: sequential());
    on<EnableSideBySideMode>(_onEnableSideBySideMode,
        transformer: sequential());
    on<DisableSideBySideMode>(_onDisableSideBySideMode,
        transformer: sequential());
    on<UpdateSplitRatio>(_onUpdateSplitRatio, transformer: sequential());
    on<SwapSideBySideTabs>(_onSwapSideBySideTabs, transformer: sequential());
  }

  void _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) {
    final tabs = _repository.loadTabs();
    final savedIndex = _repository.loadCurrentTabIndex();
    final currentTabIndex =
        tabs.isEmpty ? 0 : savedIndex.clamp(0, tabs.length - 1);
    final sideBySideMode = _repository.loadSideBySideMode();

    // ╫ץ╫ש╫ף╫ץ╫נ ╫⌐╫פ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫⌐╫£ side-by-side ╫¬╫º╫ש╫á╫ש╫¥
    SideBySideMode? validatedMode;
    if (sideBySideMode != null && tabs.isNotEmpty) {
      if (sideBySideMode.leftTabIndex < tabs.length &&
          sideBySideMode.rightTabIndex < tabs.length &&
          sideBySideMode.leftTabIndex != sideBySideMode.rightTabIndex) {
        validatedMode = sideBySideMode;
      } else {
        debugPrint('DEBUG: ╫₧╫ª╫ס side-by-side ╫£╫נ ╫¬╫º╫ש╫ƒ, ╫₧╫¬╫ó╫£╫¥');
      }
    }

    emit(state.copyWith(
      tabs: tabs,
      currentTabIndex: currentTabIndex,
      sideBySideMode: validatedMode,
    ));
  }

  Future<void> _onReplaceAllTabs(
      ReplaceAllTabs event, Emitter<TabsState> emit) async {
    debugPrint('DEBUG: ╫פ╫ק╫£╫ñ╫¬ ╫¢╫£ ╫פ╫ר╫נ╫ס╫ש╫¥ - ${event.tabs.length} ╫ר╫נ╫ס╫ש╫¥ ╫ק╫ף╫⌐╫ש╫¥');

    final tabsToDispose = List<OpenedTab>.from(state.tabs);

    emit(state.copyWith(
      tabs: event.tabs,
      currentTabIndex: event.currentTabIndex,
      clearSideBySide: true,
    ));
    await _repository.saveTabs(event.tabs, event.currentTabIndex, null);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  Future<void> _onSaveTabs(SaveTabs event, Emitter<TabsState> emit) async {
    await _repository.saveTabs(
        state.tabs, state.currentTabIndex, state.sideBySideMode);
  }

  Future<void> _onAddTab(AddTab event, Emitter<TabsState> emit) async {
    debugPrint('DEBUG: ╫פ╫ץ╫í╫ñ╫¬ ╫ר╫נ╫ס ╫ק╫ף╫⌐ - ${event.tab.title}');
    final newTabs = List<OpenedTab>.from(state.tabs);
    final newIndex = event.insertAdjacent
        ? min(state.currentTabIndex + 1, newTabs.length)
        : newTabs.length;
    newTabs.insert(newIndex, event.tab);

    // ╫ó╫ף╫¢╫ץ╫ƒ ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫ס╫₧╫ª╫ס side-by-side ╫נ╫¥ ╫º╫ש╫ש╫¥
    SideBySideMode? newSideBySideMode = state.sideBySideMode;
    if (state.sideBySideMode != null) {
      var newLeftIndex = state.sideBySideMode!.leftTabIndex;
      var newRightIndex = state.sideBySideMode!.rightTabIndex;

      // ╫נ╫¥ ╫פ╫ר╫נ╫ס ╫פ╫ק╫ף╫⌐ ╫á╫ץ╫í╫ú ╫£╫ñ╫á╫ש ╫נ╫ק╫ף ╫₧╫פ╫ר╫נ╫ס╫ש╫¥ ╫ס╫₧╫ª╫ס side-by-side, ╫₧╫ó╫ף╫¢╫á╫ש╫¥ ╫נ╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í
      if (newIndex <= newLeftIndex) newLeftIndex++;
      if (newIndex <= newRightIndex) newRightIndex++;

      newSideBySideMode = state.sideBySideMode!.copyWith(
        leftTabIndex: newLeftIndex,
        rightTabIndex: newRightIndex,
      );

      debugPrint(
          'DEBUG: ╫ó╫ף╫¢╫ץ╫ƒ ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫ס╫₧╫ª╫ס side-by-side: left=$newLeftIndex, right=$newRightIndex');
    }

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
    ));
    await _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
  }

  Future<void> _onOpenOrFocusTab(
      OpenOrFocusTab event, Emitter<TabsState> emit) async {
    final targetTitle = await _resolveTabLocationTitle(event.tab,
        explicitTitle: event.targetTitle);
    final matchingIndex = await _findMatchingTopLevelTabIndex(
      event.tab,
      targetTitle,
    );

    if (matchingIndex != null) {
      // ╫נ╫¥ ╫פ╫ר╫נ╫ס ╫פ╫ק╫ף╫⌐ ╫₧╫ס╫º╫⌐ ╫פ╫ף╫ע╫⌐╫פ ╫₧╫₧╫ץ╫º╫ף╫¬ (deep link), ╫á╫ó╫ס╫ש╫¿ ╫נ╫ץ╫¬╫פ ╫£Γאסbloc ╫⌐╫£
      // ╫פ╫ר╫נ╫ס ╫פ╫º╫ש╫ש╫¥ Γאפ ╫נ╫ק╫¿╫¬ ╫פΓאסhighlight ╫פ╫ק╫ף╫⌐ ╫פ╫ש╫פ ╫á╫צ╫¿╫º ╫ó╫¥ ╫פΓאסdispose.
      _propagatePinpointHighlightToExistingTab(
        existingTab: state.tabs[matchingIndex],
        incomingTab: event.tab,
      );
      // ╫í╫ש╫₧╫á╫ש╫ץ╫¬/╫פ╫ש╫í╫ר╫ץ╫¿╫ש╫פ: ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫ק╫¿ ╫₧╫ש╫º╫ץ╫¥ ╫í╫ñ╫ª╫ש╫ñ╫ש ╫ס╫í╫ñ╫¿, ╫ץ╫£╫נ ╫₧╫í╫ñ╫ש╫º ╫£╫פ╫ó╫ס╫ש╫¿
      // focus ╫£╫ר╫נ╫ס ╫פ╫º╫ש╫ש╫¥ Γאפ ╫ª╫¿╫ש╫ת ╫£╫ע╫£╫ץ╫£ ╫נ╫ץ╫¬╫ץ ╫£╫₧╫ש╫º╫ץ╫¥ ╫פ╫₧╫ס╫ץ╫º╫⌐.
      if (event.navigateToPositionIfReused) {
        _propagateNavigationToExistingTab(
          existingTab: state.tabs[matchingIndex],
          incomingTab: event.tab,
        );
      }
      event.tab.dispose();
      final tabsToSave = state.tabs;
      final modeToSave = state.sideBySideMode;
      emit(state.copyWith(currentTabIndex: matchingIndex));
      await _repository.saveTabs(tabsToSave, matchingIndex, modeToSave);
      return;
    }

    await _onAddTab(
      AddTab(event.tab, insertAdjacent: event.insertAdjacent),
      emit,
    );
  }

  void _propagatePinpointHighlightToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) {
    if (incomingTab is! TextBookTab) return;
    final pinpoint = incomingTab.pinpointHighlight;
    if (pinpoint == null || pinpoint.isEmpty) return;
    // pinpointHighlightSectionIndex ╫á╫⌐╫₧╫¿ ╫ó╫£ ╫פ╫ר╫נ╫ס ╫₧╫פ╫º╫ץ╫נ╫ץ╫¿╫ף╫ש╫á╫ר╫ץ╫¿ ╫ó╫¥ ╫פ╫í╫ó╫ש╫ú
    // ╫פ╫₧╫º╫ץ╫¿╫ש ╫⌐╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫ש╫º╫⌐ ╫ס╫º╫ש╫⌐╫ץ╫¿; ╫פΓאסindex ╫⌐╫£ ╫פ╫ר╫נ╫ס ╫¢╫ס╫¿ ╫ó╫£╫ץ╫£ ╫£╫פ╫⌐╫¬╫á╫ץ╫¬ ╫נ╫¥
    // ╫פ╫º╫ץ╫נ╫ץ╫¿╫ף╫ש╫á╫ר╫ץ╫¿ ╫פ╫ק╫ש╫£ fallback ╫£╫פ╫ש╫í╫ר╫ץ╫¿╫ש╫פ (╫ס╫₧╫í╫£╫ץ╫£ ╫⌐╫נ╫ש╫á╫ץ pinpoint).
    final sectionIndex =
        incomingTab.pinpointHighlightSectionIndex ?? incomingTab.index;

    final TextBookTab? targetText = _resolveTextBookTab(
      existingTab,
      incomingTab,
    );
    if (targetText == null) return;

    void dispatch() {
      targetText.bloc.add(ApplyPinpointHighlight(
        sectionIndex: sectionIndex,
        text: pinpoint,
      ));
    }

    if (targetText.bloc.state is TextBookLoaded) {
      dispatch();
      return;
    }

    // ╫פ╫ר╫נ╫ס ╫פ╫º╫ש╫ש╫¥ ╫נ╫ץ╫£╫ש ╫ó╫ף╫ש╫ש╫ƒ ╫ס╫ר╫ó╫ש╫á╫פ ╫¿╫נ╫⌐╫ץ╫á╫ש╫¬ Γאפ ╫á╫₧╫¬╫ש╫ƒ ╫£╫פ╫ע╫ó╫פ ╫£ΓאסLoaded ╫ñ╫ó╫¥ ╫נ╫ק╫¬.
    late StreamSubscription<TextBookState> sub;
    sub = targetText.bloc.stream.listen((state) {
      if (state is TextBookLoaded) {
        dispatch();
        sub.cancel();
      }
    });
  }

  TextBookTab? _resolveTextBookTab(
    OpenedTab existingTab,
    TextBookTab incomingTab,
  ) {
    if (existingTab is TextBookTab) {
      return existingTab;
    }
    // ╫סΓאסsideΓאסbyΓאסside ╫ª╫¿╫ש╫ת ╫£╫פ╫ק╫ש╫£ ╫נ╫¬ ╫פΓאסpinpoint ╫ó╫£ ╫פ╫ª╫ף ╫⌐╫₧╫¬╫נ╫ש╫¥ ╫ס╫צ╫פ╫ץ╫¬ ╫ק╫צ╫º╫פ (book id
    // / category id), ╫£╫נ ╫¿╫º ╫¢╫ץ╫¬╫¿╫¬ Γאפ ╫¢╫ף╫ש ╫⌐╫£╫נ ╫£╫ó╫ף╫¢╫ƒ ╫ס╫ר╫ó╫ץ╫¬ ╫ª╫ף ╫ó╫¥ ╫í╫ñ╫¿ ╫⌐╫ץ╫á╫פ
    // ╫⌐╫⌐╫¥ ╫פ╫º╫ץ╫ס╫Ñ ╫⌐╫£╫ץ ╫צ╫פ╫פ.
    if (existingTab is CombinedTab) {
      final right = existingTab.rightTab;
      if (right is TextBookTab && _isSameBook(right, incomingTab)) {
        return right;
      }
      final left = existingTab.leftTab;
      if (left is TextBookTab && _isSameBook(left, incomingTab)) {
        return left;
      }
    }
    return null;
  }

  PdfBookTab? _resolvePdfBookTab(
    OpenedTab existingTab,
    PdfBookTab incomingTab,
  ) {
    if (existingTab is PdfBookTab) {
      return existingTab;
    }
    if (existingTab is CombinedTab) {
      final right = existingTab.rightTab;
      if (right is PdfBookTab && _isSameBook(right, incomingTab)) {
        return right;
      }
      final left = existingTab.leftTab;
      if (left is PdfBookTab && _isSameBook(left, incomingTab)) {
        return left;
      }
    }
    return null;
  }

  /// ╫₧╫á╫ץ╫ץ╫ר ╫ר╫נ╫ס ╫º╫ש╫ש╫¥ ╫£╫₧╫ש╫º╫ץ╫¥ ╫⌐╫£ ╫פ╫ר╫נ╫ס ╫פ╫á╫¢╫á╫í (index ╫סΓאסTextBook, pageNumber ╫סΓאסPDF).
  /// ╫₧╫⌐╫₧╫⌐ ╫¢╫⌐╫ñ╫¬╫ש╫ק╫¬ ╫í╫ש╫₧╫á╫ש╫פ/╫פ╫ש╫í╫ר╫ץ╫¿╫ש╫פ ╫₧╫₧╫ק╫צ╫¿╫¬ ╫ר╫נ╫ס ╫º╫ש╫ש╫¥ Γאפ ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫ק╫¿ ╫₧╫ש╫º╫ץ╫¥ ╫í╫ñ╫ª╫ש╫ñ╫ש
  /// ╫ץ╫£╫נ ╫¿╫º ╫נ╫¬ ╫פ╫í╫ñ╫¿.
  void _propagateNavigationToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) {
    if (incomingTab is PdfBookTab) {
      final targetPdf = _resolvePdfBookTab(existingTab, incomingTab);
      if (targetPdf == null) return;
      final targetPage = incomingTab.pageNumber;
      // ╫ó╫ף╫¢╫ץ╫ƒ pageNumber ╫ס╫ר╫נ╫ס ╫¢╫ת ╫⌐╫ש╫ש╫⌐╫₧╫¿ ╫£-restore ╫ó╫¬╫ש╫ף╫ש ╫ץ╫¢╫ת ╫⌐╫נ╫¥ ╫פ╫₧╫í╫ת ╫ó╫ץ╫ף
      // ╫£╫נ ╫פ╫ª╫ר╫¿╫ú ╫£-controller, ╫פ╫ר╫ó╫ש╫á╫פ ╫פ╫ס╫נ╫פ ╫¬╫ש╫ñ╫¬╫ק ╫ס╫ó╫₧╫ץ╫ף ╫פ╫á╫¢╫ץ╫ƒ.
      targetPdf.pageNumber = targetPage;
      if (targetPdf.pdfViewerController.isReady) {
        targetPdf.pdfViewerController.goToPage(pageNumber: targetPage);
      }
      return;
    }

    if (incomingTab is TextBookTab) {
      final targetText = _resolveTextBookTab(existingTab, incomingTab);
      if (targetText == null) return;
      final targetIndex = incomingTab.index;
      // ╫ó╫ף╫¢╫ץ╫ƒ ╫נ╫ש╫á╫ף╫º╫í ╫פ╫ר╫נ╫ס ╫₧╫ש╫ש╫ף╫ש╫¬ - ╫ק╫⌐╫ץ╫ס ╫₧╫⌐╫¬╫ש ╫í╫ש╫ס╫ץ╫¬:
      // 1. saveTabs ╫¿╫Ñ ╫סΓאסfinally ╫⌐╫£ ╫פΓאסhandler ╫ץ╫ó╫£╫ץ╫£ ╫£╫פ╫ש╫⌐╫₧╫¿ ╫ó╫£ ╫פ╫₧╫ש╫º╫ץ╫¥ ╫פ╫ש╫⌐╫ƒ.
      // 2. ╫נ╫¥ ╫פ╫₧╫í╫ת ╫ó╫ץ╫ף ╫£╫נ ╫ס╫á╫פ ╫נ╫¬ ╫פ╫¿╫⌐╫ש╫₧╫פ (scrollController ╫£╫נ ╫₧╫ק╫ץ╫ס╫¿), ╫פ╫º╫¿╫ש╫נ╫פ
      //    ╫פ╫ס╫נ╫פ ╫£ΓאסinitState/load ╫¬╫ñ╫¬╫ק ╫ס╫נ╫ש╫á╫ף╫º╫í ╫פ╫צ╫פ.
      targetText.index = targetIndex;

      Future<void> dispatch() async {
        // ApplyPinpointHighlight (╫נ╫¥ ╫º╫ץ╫ף╫¥) ╫¢╫ס╫¿ ╫ע╫£╫£. ╫¢╫נ╫ƒ ╫₧╫ר╫ñ╫£╫ש╫¥ ╫ס╫₧╫º╫¿╫פ ╫⌐╫נ╫ש╫ƒ
        // pinpoint ╫נ╫ס╫£ ╫ש╫⌐ ╫ס╫º╫⌐╫¬ ╫á╫ש╫ץ╫ץ╫ר. ╫פ╫º╫ץ╫á╫ר╫¿╫ץ╫£╫¿ ╫ó╫⌐╫ץ╫ש ╫£╫פ╫ש╫ץ╫¬ ╫£╫נ ╫₧╫ק╫ץ╫ס╫¿ ╫ע╫¥
        // ╫¢╫⌐Γאסstate ╫פ╫ץ╫נ Loaded (╫פ╫¿╫⌐╫ש╫₧╫פ ╫ó╫ף╫ש╫ש╫ƒ ╫£╫נ ╫º╫ש╫ס╫£╫פ ╫נ╫¬ ╫פ╫ñ╫¿╫ש╫ש╫₧╫ש╫¥ ╫פ╫¿╫נ╫⌐╫ץ╫á╫ש╫¥),
        // ╫£╫¢╫ƒ ╫₧╫á╫í╫ש╫¥ ╫⌐╫ץ╫ס ╫ץ╫⌐╫ץ╫ס ╫ó╫ף ╫⌐╫₧╫ק╫ץ╫ס╫¿ ╫נ╫ץ ╫ó╫ף timeout ╫í╫ס╫ש╫¿.
        for (var attempt = 0; attempt < 30; attempt++) {
          if (targetText.bloc.isClosed) return;
          if (targetText.bloc.scrollController.isAttached) {
            targetText.bloc.scrollController.scrollTo(
              index: targetIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      if (targetText.bloc.state is TextBookLoaded) {
        unawaited(dispatch());
        return;
      }

      late StreamSubscription<TextBookState> sub;
      sub = targetText.bloc.stream.listen((state) {
        if (state is TextBookLoaded) {
          unawaited(dispatch());
          sub.cancel();
        }
      });
    }
  }

  Future<int?> _findMatchingTopLevelTabIndex(
    OpenedTab targetTab,
    String? normalizedTargetTitle,
  ) async {
    for (var index = 0; index < state.tabs.length; index++) {
      final openTab = state.tabs[index];
      if (await _topLevelTabMatches(
          openTab, targetTab, normalizedTargetTitle)) {
        return index;
      }
    }
    return null;
  }

  Future<bool> _topLevelTabMatches(
    OpenedTab openTab,
    OpenedTab targetTab,
    String? normalizedTargetTitle,
  ) async {
    if (await _singleTabMatches(openTab, targetTab, normalizedTargetTitle)) {
      return true;
    }

    if (openTab is CombinedTab) {
      return await _singleTabMatches(
            openTab.rightTab,
            targetTab,
            normalizedTargetTitle,
          ) ||
          await _singleTabMatches(
            openTab.leftTab,
            targetTab,
            normalizedTargetTitle,
          );
    }

    return false;
  }

  Future<bool> _singleTabMatches(
    OpenedTab openTab,
    OpenedTab targetTab,
    String? normalizedTargetTitle,
  ) async {
    if (_hasMatchingDedupeKey(openTab, targetTab)) {
      return true;
    }

    if (!_isSameBook(openTab, targetTab)) {
      return false;
    }

    final normalizedOpenTitle = await _resolveTabLocationTitle(openTab);
    return _titlesMatch(
      normalizedOpenTitle: normalizedOpenTitle,
      normalizedTargetTitle: normalizedTargetTitle,
      openTab: openTab,
      targetTab: targetTab,
    );
  }

  bool _hasMatchingDedupeKey(OpenedTab openTab, OpenedTab targetTab) {
    final openKey = openTab.dedupeKey;
    final targetKey = targetTab.dedupeKey;
    return openKey != null && targetKey != null && openKey == targetKey;
  }

  bool _isSameBook(OpenedTab openTab, OpenedTab targetTab) {
    if (openTab is TextBookTab && targetTab is TextBookTab) {
      final openIdentity = _textBookIdentity(openTab);
      final targetIdentity = _textBookIdentity(targetTab);
      if (openIdentity == null || targetIdentity == null) {
        return false;
      }
      return openIdentity == targetIdentity;
    }

    if (openTab is PdfBookTab && targetTab is PdfBookTab) {
      return openTab.book.path == targetTab.book.path;
    }

    return false;
  }

  String? _textBookIdentity(TextBookTab tab) {
    final bookId = tab.book.id;
    if (bookId != null) {
      return 'book:$bookId';
    }

    final categoryId = tab.book.categoryId;
    if (categoryId != null) {
      return 'category:$categoryId|title:${tab.book.title}|type:${tab.book.fileType ?? 'txt'}';
    }

    final externalLibraryId = tab.book.externalLibraryId;
    if (externalLibraryId != null && externalLibraryId.isNotEmpty) {
      return 'external:$externalLibraryId';
    }

    final filePath = tab.book.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      return 'file:$filePath';
    }

    return null;
  }

  Future<String?> _resolveTabLocationTitle(
    OpenedTab tab, {
    String? explicitTitle,
  }) async {
    if (tab is TextBookTab) {
      return _normalizeLocationTitle(
        tab.book.title,
        explicitTitle ??
            await _resolveTextTabLocationTitle(
              tab,
            ),
      );
    }

    if (tab is PdfBookTab) {
      return _normalizeLocationTitle(
        tab.book.title,
        explicitTitle ??
            await _resolvePdfTabLocationTitle(
              tab,
            ),
      );
    }

    return explicitTitle?.trim().isEmpty ?? true ? null : explicitTitle!.trim();
  }

  Future<String?> _resolveTextTabLocationTitle(TextBookTab tab) async {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    try {
      final ref = await refFromIndex(tab.index, tab.book.tableOfContents);
      return ref.trim().isEmpty ? null : ref;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolvePdfTabLocationTitle(PdfBookTab tab) async {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    try {
      final ref = await refFromPageNumber(
          tab.pageNumber, tab.outline.value, tab.book.title);
      if (ref.trim().isNotEmpty) {
        return ref;
      }
    } catch (_) {
      // Fall back to page-based comparison when outline is unavailable.
    }

    return null;
  }

  String? _normalizeLocationTitle(String bookTitle, String? title) {
    if (title == null) {
      return null;
    }

    var normalized = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith(bookTitle)) {
      normalized = normalized.substring(bookTitle.length).trimLeft();
      if (normalized.startsWith(',')) {
        normalized = normalized.substring(1).trimLeft();
      }
    }

    return normalized.isEmpty ? null : normalized;
  }

  bool _titlesMatch({
    required String? normalizedOpenTitle,
    required String? normalizedTargetTitle,
    required OpenedTab openTab,
    required OpenedTab targetTab,
  }) {
    if (normalizedOpenTitle != null && normalizedTargetTitle != null) {
      return normalizedOpenTitle == normalizedTargetTitle;
    }

    return _fallbackLocationKey(openTab) == _fallbackLocationKey(targetTab);
  }

  String _fallbackLocationKey(OpenedTab tab) {
    if (tab is TextBookTab) {
      return 'index:${tab.index}';
    }

    if (tab is PdfBookTab) {
      return 'page:${tab.pageNumber}';
    }

    return tab.title;
  }

  Future<void> _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final removedTabIndex = state.tabs.indexOf(event.tab);

    final newTabs = List<OpenedTab>.from(state.tabs)..remove(event.tab);

    // ╫ס╫ף╫ש╫º╫פ ╫נ╫¥ ╫פ╫ר╫נ╫ס ╫⌐╫á╫í╫ע╫¿ ╫פ╫ש╫פ ╫ק╫£╫º ╫₧╫₧╫ª╫ס side-by-side
    SideBySideMode? newSideBySideMode = state.sideBySideMode;
    if (state.sideBySideMode != null) {
      if (removedTabIndex == state.sideBySideMode!.leftTabIndex ||
          removedTabIndex == state.sideBySideMode!.rightTabIndex) {
        // ╫נ╫¥ ╫í╫ע╫¿╫á╫ץ ╫נ╫ק╫ף ╫₧╫פ╫ר╫נ╫ס╫ש╫¥ ╫ס╫₧╫ª╫ס side-by-side, ╫₧╫ס╫ר╫£╫ש╫¥ ╫נ╫¬ ╫פ╫₧╫ª╫ס
        debugPrint('DEBUG: ╫ס╫ש╫ר╫ץ╫£ ╫₧╫ª╫ס side-by-side ╫¢╫ש ╫á╫í╫ע╫¿ ╫ר╫נ╫ס ╫⌐╫פ╫ש╫פ ╫ק╫£╫º ╫₧╫₧╫á╫ץ');
        newSideBySideMode = null;
      } else {
        // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫נ╫¥ ╫פ╫¥ ╫פ╫⌐╫¬╫á╫ץ
        var newLeftIndex = state.sideBySideMode!.leftTabIndex;
        var newRightIndex = state.sideBySideMode!.rightTabIndex;

        if (removedTabIndex < newLeftIndex) newLeftIndex--;
        if (removedTabIndex < newRightIndex) newRightIndex--;

        newSideBySideMode = state.sideBySideMode!.copyWith(
          leftTabIndex: newLeftIndex,
          rightTabIndex: newRightIndex,
        );
      }
    }

    // ╫נ╫¥ ╫נ╫ש╫ƒ ╫ר╫נ╫ס╫ש╫¥ ╫á╫ץ╫¬╫¿╫ש╫¥, ╫á╫⌐╫נ╫ש╫¿ ╫נ╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫ס-0
    if (newTabs.isEmpty) {
      emit(state.copyWith(
        tabs: newTabs,
        currentTabIndex: 0,
        clearSideBySide: true,
      ));
      await _repository.saveTabs(newTabs, 0, null);
      _disposeTabLater(event.tab);
      return;
    }

    // ╫ק╫ש╫⌐╫ץ╫ס ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫ק╫ף╫⌐ - ╫נ╫¥ ╫í╫ע╫¿╫á╫ץ ╫ר╫נ╫ס ╫£╫ñ╫á╫ש ╫נ╫ץ ╫ס╫ף╫ש╫ץ╫º ╫ó╫£ ╫פ╫ר╫נ╫ס ╫פ╫ñ╫ó╫ש╫£, ╫צ╫צ╫ש╫¥ ╫נ╫ש╫á╫ף╫º╫í ╫נ╫ק╫ף ╫נ╫ק╫ץ╫¿╫פ
    var newIndex = removedTabIndex <= state.currentTabIndex
        ? max(state.currentTabIndex - 1, 0)
        : state.currentTabIndex;

    // ╫ץ╫ש╫ף╫ץ╫נ ╫⌐╫פ╫נ╫ש╫á╫ף╫º╫í ╫¬╫º╫ש╫ƒ (╫£╫נ ╫ק╫ץ╫¿╫ע ╫₧╫ע╫ס╫ץ╫£╫ץ╫¬ ╫פ╫¿╫⌐╫ש╫₧╫פ)
    newIndex = min(newIndex, newTabs.length - 1);

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
      clearSideBySide: newSideBySideMode == null,
    ));
    await _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
    _disposeTabLater(event.tab);
  }

  Future<void> _onSetCurrentTab(
      SetCurrentTab event, Emitter<TabsState> emit) async {
    if (event.index >= 0 && event.index < state.tabs.length) {
      // ╫£╫נ ╫₧╫ס╫ר╫£╫ש╫¥ ╫נ╫¬ ╫₧╫ª╫ס side-by-side - ╫ñ╫⌐╫ץ╫ר ╫ó╫ץ╫ס╫¿╫ש╫¥ ╫£╫ר╫נ╫ס
      // ╫פ╫ñ╫ץ╫á╫º╫ª╫ש╫פ _shouldShowSideBySideView ╫¬╫ק╫£╫ש╫ר ╫נ╫¥ ╫£╫פ╫ª╫ש╫ע side-by-side ╫נ╫ץ TabBarView
      final tabsToSave = state.tabs;
      final modeToSave = state.sideBySideMode;
      emit(state.copyWith(currentTabIndex: event.index));
      await _repository.saveTabs(tabsToSave, event.index, modeToSave);
    }
  }

  void _onCloseCurrentTab(CloseCurrentTab event, Emitter<TabsState> emit) {
    if (state.tabs.isEmpty || state.currentTabIndex >= state.tabs.length) {
      return;
    }
    add(RemoveTab(state.tabs[state.currentTabIndex]));
  }

  Future<void> _onCloseAllTabs(
      CloseAllTabs event, Emitter<TabsState> emit) async {
    // ╫⌐╫₧╫ש╫¿╫¬ ╫ר╫נ╫ס╫ש╫¥ ╫₧╫ץ╫ª╫₧╫ף╫ש╫¥ ╫ס╫£╫ס╫ף
    final pinnedTabs = state.tabs.where((tab) => tab.isPinned).toList();
    final tabsToDispose = state.tabs.where((tab) => !tab.isPinned).toList();

    // ╫נ╫¥ ╫ש╫⌐ ╫ר╫נ╫ס╫ש╫¥ ╫₧╫ץ╫ª╫₧╫ף╫ש╫¥, ╫á╫⌐╫נ╫ש╫¿ ╫נ╫ץ╫¬╫¥
    final newIndex = pinnedTabs.isNotEmpty ? 0 : 0;

    // ╫ס╫ש╫ר╫ץ╫£ ╫₧╫ª╫ס side-by-side ╫¢╫ש ╫í╫ע╫¿╫á╫ץ ╫ר╫נ╫ס╫ש╫¥
    emit(state.copyWith(
      tabs: pinnedTabs,
      currentTabIndex: newIndex,
      clearSideBySide: true,
    ));
    await _repository.saveTabs(pinnedTabs, newIndex, null);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  Future<void> _onCloseOtherTabs(
      CloseOtherTabs event, Emitter<TabsState> emit) async {
    final tabsToDispose =
        state.tabs.where((tab) => tab != event.keepTab).toList();

    final newTabs = [event.keepTab];

    // ╫ס╫ש╫ר╫ץ╫£ ╫₧╫ª╫ס side-by-side ╫¢╫ש ╫á╫⌐╫נ╫¿ ╫¿╫º ╫ר╫נ╫ס ╫נ╫ק╫ף
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: 0,
      clearSideBySide: true,
    ));
    await _repository.saveTabs(newTabs, 0, null);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  void _onCloneTab(CloneTab event, Emitter<TabsState> emit) {
    add(AddTab(OpenedTab.from(event.tab), insertAdjacent: true));
  }

  Future<void> _onMoveTab(MoveTab event, Emitter<TabsState> emit) async {
    final newTabs = List<OpenedTab>.from(state.tabs);
    final currentTab = newTabs[state.currentTabIndex];
    final oldIndex = newTabs.indexOf(event.tab);
    newTabs.remove(event.tab);
    newTabs.insert(event.newIndex, event.tab);
    final newIndex = newTabs.indexOf(currentTab);

    // ╫ó╫ף╫¢╫ץ╫ƒ ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫ס╫₧╫ª╫ס side-by-side ╫נ╫¥ ╫º╫ש╫ש╫¥
    SideBySideMode? newSideBySideMode = state.sideBySideMode;
    if (state.sideBySideMode != null) {
      var newLeftIndex = state.sideBySideMode!.leftTabIndex;
      var newRightIndex = state.sideBySideMode!.rightTabIndex;

      // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫£╫ñ╫ש ╫פ╫¬╫צ╫ץ╫צ╫פ
      if (oldIndex == newLeftIndex) {
        newLeftIndex = event.newIndex;
      } else if (oldIndex < newLeftIndex && event.newIndex >= newLeftIndex) {
        newLeftIndex--;
      } else if (oldIndex > newLeftIndex && event.newIndex <= newLeftIndex) {
        newLeftIndex++;
      }

      if (oldIndex == newRightIndex) {
        newRightIndex = event.newIndex;
      } else if (oldIndex < newRightIndex && event.newIndex >= newRightIndex) {
        newRightIndex--;
      } else if (oldIndex > newRightIndex && event.newIndex <= newRightIndex) {
        newRightIndex++;
      }

      newSideBySideMode = state.sideBySideMode!.copyWith(
        leftTabIndex: newLeftIndex,
        rightTabIndex: newRightIndex,
      );
    }

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
    ));
    await _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
  }

  Future<void> _onNavigateToNextTab(
      NavigateToNextTab event, Emitter<TabsState> emit) async {
    if (state.tabs.isEmpty) return;
    final newIndex = (state.currentTabIndex + 1) % state.tabs.length;
    final tabsToSave = state.tabs;
    emit(state.copyWith(currentTabIndex: newIndex));
    await _repository.saveTabs(tabsToSave, newIndex);
  }

  Future<void> _onNavigateToPreviousTab(
      NavigateToPreviousTab event, Emitter<TabsState> emit) async {
    if (state.tabs.isEmpty) return;
    final newIndex = state.currentTabIndex == 0
        ? state.tabs.length - 1
        : state.currentTabIndex - 1;
    final tabsToSave = state.tabs;
    emit(state.copyWith(currentTabIndex: newIndex));
    await _repository.saveTabs(tabsToSave, newIndex);
  }

  Future<void> _onTogglePinTab(
      TogglePinTab event, Emitter<TabsState> emit) async {
    final tabIndex = state.tabs.indexOf(event.tab);
    if (tabIndex == -1) return;

    // ╫פ╫ק╫£╫ñ╫¬ ╫₧╫ª╫ס ╫פ╫פ╫ª╫₧╫ף╫פ
    event.tab.isPinned = !event.tab.isPinned;

    debugPrint(
        'DEBUG: ╫פ╫ª╫₧╫ף╫¬ ╫ר╫נ╫ס ${event.tab.title} - isPinned: ${event.tab.isPinned}');

    // ╫ש╫ª╫ש╫¿╫¬ ╫¿╫⌐╫ש╫₧╫פ ╫ק╫ף╫⌐╫פ ╫£╫ק╫£╫ץ╫ר╫ש╫ƒ ╫¢╫ף╫ש ╫£╫ע╫¿╫ץ╫¥ ╫£-Equatable ╫£╫צ╫פ╫ץ╫¬ ╫⌐╫ש╫á╫ץ╫ש
    final newTabs = List<OpenedTab>.from(state.tabs);

    // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ-state ╫¢╫ף╫ש ╫£╫ע╫¿╫ץ╫¥ ╫£-rebuild - ╫ó╫¥ forceUpdate
    final indexToSave = state.currentTabIndex;
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: state.currentTabIndex,
      forceUpdate: true,
    ));
    // ╫⌐╫₧╫ש╫¿╫¬ ╫פ╫⌐╫ש╫á╫ץ╫ש╫ש╫¥
    await _repository.saveTabs(newTabs, indexToSave);
  }

  Future<void> _onEnableSideBySideMode(
      EnableSideBySideMode event, Emitter<TabsState> emit) async {
    final rightIndex = state.tabs.indexOf(event.rightTab);
    final leftIndex = state.tabs.indexOf(event.leftTab);

    if (rightIndex == -1 || leftIndex == -1) {
      debugPrint('ERROR: ╫£╫נ ╫á╫₧╫ª╫נ╫ץ ╫פ╫ר╫נ╫ס╫ש╫¥ ╫£╫₧╫ª╫ס side-by-side');
      return;
    }

    debugPrint(
        'DEBUG: ╫פ╫ñ╫ó╫£╫¬ ╫₧╫ª╫ס side-by-side: right=${event.rightTab.title}, left=${event.leftTab.title}');

    // ╫ש╫ª╫ש╫¿╫¬ ╫ó╫ץ╫¬╫º╫ש╫¥ ╫á╫ñ╫¿╫ף╫ש╫¥ ╫¢╫ף╫ש ╫£╫נ ╫£╫⌐╫¬╫ú controllers ╫ó╫¥ ╫פ╫ר╫נ╫ס╫ש╫¥ ╫⌐╫ó╫ף╫ש╫ש╫ƒ ╫₧╫ñ╫ץ╫¿╫º╫ש╫¥ ╫₧╫פ╫ó╫Ñ.
    final combinedTab = CombinedTab(
      rightTab: OpenedTab.from(event.rightTab),
      leftTab: OpenedTab.from(event.leftTab),
      isPinned: event.rightTab.isPinned || event.leftTab.isPinned,
    );

    // ╫פ╫í╫¿╫¬ ╫⌐╫á╫ש ╫פ╫ר╫נ╫ס╫ש╫¥ ╫פ╫₧╫º╫ץ╫¿╫ש╫ש╫¥ ╫ץ╫פ╫ץ╫í╫ñ╫¬ ╫פ╫ר╫נ╫ס ╫פ╫₧╫⌐╫ץ╫£╫ס ╫ס╫₧╫º╫ץ╫₧╫¥
    final newTabs = List<OpenedTab>.from(state.tabs);

    // ╫₧╫ץ╫ª╫נ╫ש╫¥ ╫נ╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫₧╫ץ╫ת ╫ש╫ץ╫¬╫¿ ╫¢╫ף╫ש ╫£╫פ╫¢╫á╫ש╫í ╫⌐╫¥ ╫נ╫¬ ╫פ╫ר╫נ╫ס ╫פ╫₧╫⌐╫ץ╫£╫ס
    final insertIndex = rightIndex < leftIndex ? rightIndex : leftIndex;

    // ╫₧╫í╫ש╫¿╫ש╫¥ ╫נ╫¬ ╫⌐╫á╫ש ╫פ╫ר╫נ╫ס╫ש╫¥ (╫₧╫פ╫ע╫ס╫ץ╫פ ╫£╫á╫₧╫ץ╫ת ╫¢╫ף╫ש ╫£╫נ ╫£╫⌐╫ס╫⌐ ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥)
    if (rightIndex > leftIndex) {
      newTabs.removeAt(rightIndex);
      newTabs.removeAt(leftIndex);
    } else {
      newTabs.removeAt(leftIndex);
      newTabs.removeAt(rightIndex);
    }

    // ╫₧╫ץ╫í╫ש╫ñ╫ש╫¥ ╫נ╫¬ ╫פ╫ר╫נ╫ס ╫פ╫₧╫⌐╫ץ╫£╫ס
    newTabs.insert(insertIndex, combinedTab);

    // ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫ש╫פ╫ש╫פ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫⌐╫£ ╫פ╫ר╫נ╫ס ╫פ╫₧╫⌐╫ץ╫£╫ס
    final newCurrentIndex = insertIndex;

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newCurrentIndex,
      clearSideBySide: true,
      forceUpdate: true,
    ));
    await _repository.saveTabs(newTabs, newCurrentIndex, null);

    _disposeTabLater(event.rightTab);
    _disposeTabLater(event.leftTab);
  }

  Future<void> _onDisableSideBySideMode(
      DisableSideBySideMode event, Emitter<TabsState> emit) async {
    // ╫נ╫¥ ╫פ╫ר╫נ╫ס ╫פ╫₧╫ס╫ץ╫º╫⌐ ╫פ╫ץ╫נ CombinedTab, ╫á╫ñ╫¿╫º ╫נ╫ץ╫¬╫ץ ╫£╫⌐╫á╫ש ╫ר╫נ╫ס╫ש╫¥ ╫á╫ñ╫¿╫ף╫ש╫¥
    if (event.tabIndex >= 0 &&
        event.tabIndex < state.tabs.length &&
        state.tabs[event.tabIndex] is CombinedTab) {
      final combinedTab = state.tabs[event.tabIndex] as CombinedTab;
      final newTabs = List<OpenedTab>.from(state.tabs);
      final combinedIndex = event.tabIndex;

      // ╫₧╫í╫ש╫¿╫ש╫¥ ╫נ╫¬ ╫פ╫ר╫נ╫ס ╫פ╫₧╫⌐╫ץ╫£╫ס
      newTabs.removeAt(combinedIndex);

      // ╫₧╫ץ╫í╫ש╫ñ╫ש╫¥ ╫ó╫ץ╫¬╫º╫ש╫¥ ╫á╫ñ╫¿╫ף╫ש╫¥ ╫¢╫ף╫ש ╫£╫נ ╫£╫⌐╫¬╫ú controllers ╫ó╫¥ ╫פ-combined view
      newTabs.insert(combinedIndex, OpenedTab.from(combinedTab.rightTab));
      newTabs.insert(combinedIndex + 1, OpenedTab.from(combinedTab.leftTab));

      // ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫ש╫פ╫ש╫פ ╫פ╫ר╫נ╫ס ╫פ╫ש╫₧╫á╫ש
      final newCurrentIndex = combinedIndex;

      emit(state.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
        clearSideBySide: true,
        forceUpdate: true,
      ));
      await _repository.saveTabs(newTabs, newCurrentIndex, null);

      _disposeTabLater(combinedTab);
    } else {
      // ╫נ╫¥ ╫צ╫פ ╫£╫נ ╫ר╫נ╫ס ╫₧╫⌐╫ץ╫£╫ס, ╫ñ╫⌐╫ץ╫ר ╫₧╫á╫º╫ש╫¥ ╫נ╫¬ ╫פ╫₧╫ª╫ס
      final tabsToSave = state.tabs;
      final indexToSave = state.currentTabIndex;
      emit(state.copyWith(
        clearSideBySide: true,
        forceUpdate: true,
      ));
      await _repository.saveTabs(tabsToSave, indexToSave, null);
    }
  }

  Future<void> _onUpdateSplitRatio(
      UpdateSplitRatio event, Emitter<TabsState> emit) async {
    // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫ש╫ק╫í ╫⌐╫£ ╫פ╫ר╫נ╫ס ╫פ╫₧╫⌐╫ץ╫£╫ס
    if (state.currentTab is CombinedTab) {
      final combinedTab = state.currentTab as CombinedTab;
      combinedTab.splitRatio = event.ratio;

      // ╫⌐╫₧╫ש╫¿╫¬ ╫פ╫⌐╫ש╫á╫ץ╫ש
      final tabsToSave = state.tabs;
      final indexToSave = state.currentTabIndex;
      emit(state.copyWith(
        forceUpdate: true,
      ));
      await _repository.saveTabs(tabsToSave, indexToSave, null);
    }
  }

  Future<void> _onSwapSideBySideTabs(
      SwapSideBySideTabs event, Emitter<TabsState> emit) async {
    // ╫פ╫ק╫£╫ñ╫¬ ╫ª╫ף╫ף╫ש╫¥ ╫ס╫ר╫נ╫ס ╫פ╫₧╫⌐╫ץ╫£╫ס
    if (state.currentTab is CombinedTab) {
      final combinedTab = state.currentTab as CombinedTab;

      debugPrint('DEBUG: ╫פ╫ק╫£╫ñ╫¬ ╫ª╫ף╫ף╫ש╫¥ ╫ס╫₧╫ª╫ס side-by-side');

      // ╫ש╫ª╫ש╫¿╫¬ ╫ר╫נ╫ס ╫₧╫⌐╫ץ╫£╫ס ╫ק╫ף╫⌐ ╫ó╫¥ ╫ó╫ץ╫¬╫º╫ש╫¥ ╫á╫ñ╫¿╫ף╫ש╫¥ ╫⌐╫£ ╫פ╫ר╫נ╫ס╫ש╫¥ ╫פ╫₧╫ץ╫ק╫£╫ñ╫ש╫¥.
      final newCombinedTab = CombinedTab(
        rightTab: OpenedTab.from(combinedTab.leftTab),
        leftTab: OpenedTab.from(combinedTab.rightTab),
        splitRatio: 1.0 - combinedTab.splitRatio,
        isPinned: combinedTab.isPinned,
      );

      // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫¿╫⌐╫ש╫₧╫פ
      final newTabs = List<OpenedTab>.from(state.tabs);
      newTabs[state.currentTabIndex] = newCombinedTab;

      final indexToSave = state.currentTabIndex;
      emit(state.copyWith(
        tabs: newTabs,
        forceUpdate: true,
      ));
      await _repository.saveTabs(newTabs, indexToSave, null);

      _disposeTabLater(combinedTab);
    }
  }
}
