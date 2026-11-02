import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/companion/companion_books.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// Finds the companion line written on the same base line as [primaryLine],
/// or `null` when there is none.
typedef CompanionLineResolver = Future<int?> Function(int primaryLine);

/// Scrolls the companion pane to follow the primary pane, through the base
/// text line both books are written on.
class CompanionBookSync {
  CompanionBookSync({
    required this.primary,
    required this.companion,
    CompanionLineResolver? resolveCompanionLine,
    this.debounce = const Duration(milliseconds: 300),
  }) {
    _resolve = resolveCompanionLine ?? _resolveFromLinks;
    primary.lines.position.addListener(_onPrimaryPosition);
    if (resolveCompanionLine != null) {
      _onPrimaryPosition();
      return;
    }
    final initialState = primary.blocState;
    var linksByLine = initialState is TextBookLoaded
        ? initialState.linksByLine
        : null;
    _stateSubscription = primary.bloc.stream.listen((state) {
      if (state is! TextBookLoaded ||
          identical(linksByLine, state.linksByLine)) {
        return;
      }
      linksByLine = state.linksByLine;
      final line = _lastPrimaryLine;
      if (line != null) _schedule(line);
    });
    _onPrimaryPosition();
  }

  final TextBookTab primary;
  final TextBookTab companion;
  final Duration debounce;
  late final CompanionLineResolver _resolve;

  Timer? _timer;
  StreamSubscription<TextBookState>? _stateSubscription;
  int? _lastPrimaryLine;
  int? _lastCompanionLine;
  int _generation = 0;
  bool _disposed = false;

  /// Base line to companion line; `null` marks a base line with no companion.
  final Map<String, int?> _companionByBase = {};

  void _onPrimaryPosition() {
    final line = primary.lines.position.value?.topLine ?? primary.index;
    if (line == _lastPrimaryLine) return;
    _lastPrimaryLine = line;
    _schedule(line);
  }

  void _schedule(int line) {
    _timer?.cancel();
    final generation = ++_generation;
    _timer = Timer(debounce, () => _syncTo(line, generation));
  }

  Future<void> _syncTo(int primaryLine, int generation) async {
    int? target;
    try {
      target = await _resolve(primaryLine);
    } catch (e) {
      debugPrint('Companion sync failed for line $primaryLine: $e');
      return;
    }
    // A newer position arrived while this one resolved.
    if (_disposed || generation != _generation) return;
    if (target == null || target == _lastCompanionLine) return;
    _lastCompanionLine = target;
    await companion.lines.scrollToLine(target, rememberPosition: false);
  }

  /// How far back to look for a line with a base link, past headings.
  static const int _maxLookBack = 8;

  Future<int?> _resolveFromLinks(int primaryLine) async {
    final state = primary.blocState;
    if (state is! TextBookLoaded) return null;
    final companionTitle = companionTitleOf(state.book);
    if (companionTitle == null) return null;

    final baseLink = baseLinkNear(state.linksByLine, primaryLine);
    if (baseLink == null) return null;
    final baseKey = '${baseLink.path2}:${baseLink.index2}';
    if (_companionByBase.containsKey(baseKey)) return _companionByBase[baseKey];

    final siblings = await primary.bloc.repository.getSiblingCommentaries(
      sourceBookTitle: utils.getTitleFromPath(baseLink.path2),
      sourceCategoryId: baseLink.targetCategoryId,
      sourceBookSource: baseLink.targetSource,
      sourceLineIndex: baseLink.index2 - 1,
      currentBookTitle: state.book.title,
      currentCategoryId: state.book.categoryId,
      currentBookSource: state.book.source,
      requireExactLine: true,
    );
    int? line;
    for (final link in siblings) {
      if (utils.getTitleFromPath(link.path2) == companionTitle &&
          link.targetSource.isOfficial) {
        line = link.index2 - 1;
        break;
      }
    }
    _companionByBase[baseKey] = line;
    return line;
  }

  /// The base text link of [line], or of the nearest line above it that has
  /// one. [linksByLine] is keyed by one-based line numbers.
  @visibleForTesting
  static Link? baseLinkNear(Map<int, List<Link>> linksByLine, int line) {
    for (var i = line; i >= 0 && i >= line - _maxLookBack; i--) {
      Link? best;
      for (final link in linksByLine[i + 1] ?? const <Link>[]) {
        if (!LinkTypes.isVirtualSource(link.connectionType)) continue;
        // The declared base relation wins over a citation stored in reverse.
        if (best == null || link.baseProvenance > best.baseProvenance) {
          best = link;
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _stateSubscription?.cancel();
    primary.lines.position.removeListener(_onPrimaryPosition);
  }
}

/// Keeps a [CompanionBookSync] running while [tab] is a primary and companion
/// pair. Always in the tree, so splitting a tab does not change its shape.
class CompanionBookSyncScope extends StatefulWidget {
  const CompanionBookSyncScope({
    super.key,
    required this.tab,
    required this.child,
  });

  final OpenedTab tab;
  final Widget child;

  @override
  State<CompanionBookSyncScope> createState() => _CompanionBookSyncScopeState();
}

class _CompanionBookSyncScopeState extends State<CompanionBookSyncScope> {
  CompanionBookSync? _sync;

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(CompanionBookSyncScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final pair = companionPairOf(widget.tab);
    final sync = _sync;
    if (sync != null &&
        pair != null &&
        identical(sync.primary, pair.primary) &&
        identical(sync.companion, pair.companion)) {
      return;
    }
    sync?.dispose();
    _sync = pair == null
        ? null
        : CompanionBookSync(primary: pair.primary, companion: pair.companion);
  }

  @override
  void dispose() {
    _sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
