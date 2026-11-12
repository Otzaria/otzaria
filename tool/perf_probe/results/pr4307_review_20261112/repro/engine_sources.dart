part of 'benchmark.dart';

class BaselineEngine extends Engine {
  BaselineEngine(super.snapshot);

  void _applyContentRanges(
    String bookTitle,
    List<BookContentRangeChunk> ranges,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    final applicable = ranges.where((range) => range.lines.isNotEmpty).toList();
    if (currentState.book.title != bookTitle || applicable.isEmpty) {
      return;
    }

    // טווח שהוחל בפועל = טעינת-טווחים עובדת לספר הזה (תנאי לשחרור תוכן).
    _ensureLoadedContentTrackingBook(currentState.book);
    _supportsContentRangeLoading = true;

    // Repeating an already-loaded range in a full-book List must not copy the
    // entire book. A no-op still records range coverage for tab suspension.
    // Keep the regular path for missing flags, extensions, or changed lines.
    final content = currentState.content;
    final flags = _loadedContentFlags;
    if (flags.length >= content.length &&
        applicable.every((range) {
          final end = range.startLine + range.lines.length;
          if (end > content.length) return false;
          for (var index = max(0, range.startLine); index < end; index++) {
            if (!flags[index] ||
                content[index] != range.lines[index - range.startLine]) {
              return false;
            }
          }
          return true;
        })) {
      for (final range in applicable) {
        _markLoadedContentRange(
          currentState.book,
          range.startLine,
          range.startLine + range.lines.length - 1,
          totalLines: range.totalLines,
        );
      }
      return;
    }

    final nextContent = List<String>.of(currentState.content);
    final hasTrackedFlags = identical(
      currentState.loadedLineFlags,
      _loadedContentFlags,
    );
    final nextLoadedFlags = List<bool>.of(_loadedContentFlags);
    var hasContentChanged = false;
    var hasLoadedFlagsChanged = false;

    for (final range in applicable) {
      final targetLength = range.startLine + range.lines.length;
      if (nextContent.length < targetLength) {
        hasContentChanged = true;
        nextContent.addAll(
          List<String>.filled(targetLength - nextContent.length, ''),
        );
      }
      if (nextLoadedFlags.length < targetLength) {
        hasLoadedFlagsChanged = true;
        nextLoadedFlags.addAll(
          List<bool>.filled(targetLength - nextLoadedFlags.length, false),
        );
      }

      for (var offset = 0; offset < range.lines.length; offset++) {
        final targetIndex = range.startLine + offset;
        if (targetIndex >= 0 && targetIndex < nextContent.length) {
          if (nextContent[targetIndex] != range.lines[offset]) {
            hasContentChanged = true;
          }
          if (!nextLoadedFlags[targetIndex]) {
            hasLoadedFlagsChanged = true;
          }
          nextContent[targetIndex] = range.lines[offset];
          nextLoadedFlags[targetIndex] = true;
        }
      }
    }

    void markAllRanges() {
      for (final range in applicable) {
        _markLoadedContentRange(
          currentState.book,
          range.startLine,
          range.startLine + range.lines.length - 1,
          totalLines: range.totalLines,
        );
      }
    }

    if (!hasContentChanged && !hasLoadedFlagsChanged) {
      markAllRanges();
      return;
    }

    _setLoadedContentFlags(currentState.book, nextLoadedFlags);
    markAllRanges();

    emit(
      _withInlineNotesCommentator(
        currentState.copyWith(
          content: nextContent,
          contentVersion: currentState.contentVersion + 1,
          loadedLineFlags: _loadedContentFlags,
          contentChanges: ContentLineChanges(
            fromVersion: currentState.contentVersion,
            ranges: [
              if (!hasTrackedFlags && nextContent.isNotEmpty)
                (first: 0, last: nextContent.length - 1)
              else
                for (final range in applicable)
                  if (range.startLine + range.lines.length > 0)
                    (
                      first: range.startLine.clamp(0, nextContent.length - 1),
                      last: (range.startLine + range.lines.length - 1).clamp(
                        0,
                        nextContent.length - 1,
                      ),
                    ),
            ],
          ),
        ),
        // סורקים הערות רק בטווחים החדשים, בלי לחזור על כל הספר.
        scanOnly: [for (final range in applicable) ...range.lines],
      ),
    );
  }

  void _releaseContentOutsideWindow(
    TextBookLoaded currentState,
    Emitter<TextBookState> emit,
  ) {
    final content = currentState.content;
    if (!_supportsContentRangeLoading ||
        content.length < _releaseContentMinLines) {
      return;
    }

    final window = _calculateContentWindow(
      currentState,
      currentState.visibleIndices,
    );
    final keepStart = window.startLine.clamp(0, content.length - 1);
    final keepEnd = window.endLine.clamp(0, content.length - 1);

    final flags = _loadedContentFlags;
    var hasLoadedOutsideWindow = false;
    for (var i = 0; i < content.length; i++) {
      if (i >= keepStart && i <= keepEnd) {
        continue;
      }
      if (content[i].isNotEmpty) {
        hasLoadedOutsideWindow = true;
        break;
      }
    }
    if (!hasLoadedOutsideWindow) {
      return;
    }

    final nextContent = List<String>.filled(content.length, '');
    final nextFlags = List<bool>.filled(content.length, false);
    for (var i = keepStart; i <= keepEnd; i++) {
      nextContent[i] = content[i];
      nextFlags[i] = i < flags.length ? flags[i] : content[i].isNotEmpty;
    }

    _loadedContentRanges = const [];
    _setLoadedContentFlags(currentState.book, nextFlags);
    _markLoadedContentRange(currentState.book, keepStart, keepEnd);

    emit(
      currentState.copyWith(
        content: nextContent,
        contentVersion: currentState.contentVersion + 1,
        loadedLineFlags: _loadedContentFlags,
      ),
    );
  }

  void _setLoadedContentFlags(TextBook book, List<bool> loadedFlags) {
    _ensureLoadedContentTrackingBook(book);
    _loadedContentFlags = List<bool>.unmodifiable(loadedFlags);
  }

  void _onApplyFullBookContent(
    ApplyFullBookContent event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    if (currentState.book.title != event.bookTitle) {
      return;
    }

    final nextLoadedFlags = List<bool>.filled(event.content.length, true);
    final hasLoadedFlagsChanged =
        _loadedContentFlags.length != event.content.length ||
        _loadedContentFlags.any((loaded) => !loaded);
    if (listEquals(currentState.content, event.content) &&
        !hasLoadedFlagsChanged) {
      return;
    }

    _setLoadedContentFlags(currentState.book, nextLoadedFlags);

    final updatedState = _withInlineNotesCommentator(
      currentState.copyWith(
        content: event.content,
        contentVersion: currentState.contentVersion + 1,
        loadedLineFlags: _loadedContentFlags,
      ),
    );
    // אחרי שסרקנו את התוכן המלא, אין יותר טעם בסריקה נוספת על הרחבות
    // טווח עתידיות — או שכבר הוסף 'הערות' ל-availableCommentators (ואז
    // early-return שומר עלינו), או שאין הערות בכלל בספר.
    _inlineNotesFullScanDone = true;
    emit(updatedState);
    _markLoadedContentRange(
      currentState.book,
      0,
      event.content.isEmpty ? 0 : event.content.length - 1,
      totalLines: event.content.length,
    );
  }

  List<String> _contentWithAppliedRange(BookContentRange range) {
    final content = List<String>.filled(_fullContentLength(range), '');
    for (var offset = 0; offset < range.lines.length; offset++) {
      final targetIndex = range.startLine + offset;
      if (targetIndex >= 0 && targetIndex < content.length) {
        content[targetIndex] = range.lines[offset];
      }
    }
    return content;
  }

  List<bool> _loadedContentFlagsWithAppliedRange(BookContentRange range) {
    final loadedFlags = List<bool>.filled(_fullContentLength(range), false);
    for (var offset = 0; offset < range.lines.length; offset++) {
      final targetIndex = range.startLine + offset;
      if (targetIndex >= 0 && targetIndex < loadedFlags.length) {
        loadedFlags[targetIndex] = true;
      }
    }
    return loadedFlags;
  }

}

class CandidateEngine extends Engine {
  CandidateEngine(super.snapshot);

  void _applyContentRanges(
    String bookTitle,
    List<BookContentRangeChunk> ranges,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    final applicable = ranges.where((range) => range.lines.isNotEmpty).toList();
    if (currentState.book.title != bookTitle || applicable.isEmpty) {
      return;
    }

    // טווח שהוחל בפועל = טעינת-טווחים עובדת לספר הזה (תנאי לשחרור תוכן).
    _ensureLoadedContentTrackingBook(currentState.book);
    _supportsContentRangeLoading = true;

    void markAllRanges() {
      for (final range in applicable) {
        _markLoadedContentRange(
          currentState.book,
          range.startLine,
          range.startLine + range.lines.length - 1,
          totalLines: range.totalLines,
        );
      }
    }

    // תוכן מלא עשוי עדיין להיות רשימה רגילה. ב-no-op אין snapshot חדש,
    // ולכן המרה לפני בדיקת הטווח הייתה חוזרת על כל הספר בכל אירוע זהה.
    if ((currentState.content is! ChunkedList<String> ||
            _loadedContentFlags is! ChunkedList<bool>) &&
        _loadedContentFlags.length >= currentState.content.length &&
        applicable.every((range) {
          final end = range.startLine + range.lines.length;
          if (end > currentState.content.length) return false;
          for (var index = max(0, range.startLine); index < end; index++) {
            if (!_loadedContentFlags[index] ||
                currentState.content[index] !=
                    range.lines[index - range.startLine]) {
              return false;
            }
          }
          return true;
        })) {
      markAllRanges();
      return;
    }

    final nextContent = ChunkedList<String>.from(
      currentState.content,
      defaultValue: '',
    ).edit();
    final hasTrackedFlags = identical(
      currentState.loadedLineFlags,
      _loadedContentFlags,
    );
    final nextLoadedFlags = ChunkedList<bool>.from(
      _loadedContentFlags,
      defaultValue: false,
    ).edit();
    if (nextLoadedFlags.length < nextContent.length) {
      nextLoadedFlags.length = nextContent.length;
    }

    for (final range in applicable) {
      final targetLength = range.startLine + range.lines.length;
      if (nextContent.length < targetLength) {
        nextContent.length = targetLength;
      }
      if (nextLoadedFlags.length < targetLength) {
        nextLoadedFlags.length = targetLength;
      }

      final first = max(0, range.startLine);
      if (first < targetLength) {
        nextContent.setRange(
          first,
          targetLength,
          range.lines,
          first - range.startLine,
        );
        nextLoadedFlags.fillRange(first, targetLength, true);
      }
    }

    if (!nextContent.changed && !nextLoadedFlags.changed) {
      markAllRanges();
      return;
    }

    _setLoadedContentFlags(currentState.book, nextLoadedFlags.build());
    markAllRanges();

    emit(
      _withInlineNotesCommentator(
        currentState.copyWith(
          content: nextContent.build(),
          contentVersion: currentState.contentVersion + 1,
          loadedLineFlags: _loadedContentFlags,
          contentChanges: ContentLineChanges(
            fromVersion: currentState.contentVersion,
            ranges: [
              if (!hasTrackedFlags && nextContent.isNotEmpty)
                (first: 0, last: nextContent.length - 1)
              else
                for (final range in applicable)
                  if (range.startLine + range.lines.length > 0)
                    (
                      first: range.startLine.clamp(0, nextContent.length - 1),
                      last: (range.startLine + range.lines.length - 1).clamp(
                        0,
                        nextContent.length - 1,
                      ),
                    ),
            ],
          ),
        ),
        // סורקים הערות רק בטווחים החדשים, בלי לחזור על כל הספר.
        scanOnly: [for (final range in applicable) ...range.lines],
      ),
    );
  }

  void _releaseContentOutsideWindow(
    TextBookLoaded currentState,
    Emitter<TextBookState> emit,
  ) {
    final content = currentState.content;
    if (!_supportsContentRangeLoading ||
        content.length < _releaseContentMinLines) {
      return;
    }

    final window = _calculateContentWindow(
      currentState,
      currentState.visibleIndices,
    );
    final keepStart = window.startLine.clamp(0, content.length - 1);
    final keepEnd = window.endLine.clamp(0, content.length - 1);

    final flags = _loadedContentFlags;
    final sourceContent = ChunkedList<String>.from(content, defaultValue: '');
    final nextContent = sourceContent.retainRange(keepStart, keepEnd + 1);
    final nextFlags = ChunkedList<bool>.from(flags, defaultValue: false).edit()
      ..length = content.length
      ..retainRange(keepStart, keepEnd + 1);
    for (var i = keepStart; i <= keepEnd; i++) {
      if (i >= flags.length) nextFlags[i] = content[i].isNotEmpty;
    }
    if (identical(nextContent, sourceContent) && !nextFlags.changed) return;

    _loadedContentRanges = const [];
    _setLoadedContentFlags(currentState.book, nextFlags.build());
    _markLoadedContentRange(currentState.book, keepStart, keepEnd);

    emit(
      currentState.copyWith(
        content: nextContent,
        contentVersion: currentState.contentVersion + 1,
        loadedLineFlags: _loadedContentFlags,
      ),
    );
  }

  void _setLoadedContentFlags(TextBook book, List<bool> loadedFlags) {
    _ensureLoadedContentTrackingBook(book);
    _loadedContentFlags = loadedFlags is ChunkedList<bool>
        ? loadedFlags
        : List<bool>.unmodifiable(loadedFlags);
  }

  void _onApplyFullBookContent(
    ApplyFullBookContent event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    if (currentState.book.title != event.bookTitle) {
      return;
    }

    final nextLoadedFlags = List<bool>.filled(event.content.length, true);
    final hasLoadedFlagsChanged =
        _loadedContentFlags.length != event.content.length ||
        _loadedContentFlags.any((loaded) => !loaded);
    if (listEquals(currentState.content, event.content) &&
        !hasLoadedFlagsChanged) {
      return;
    }

    _setLoadedContentFlags(currentState.book, nextLoadedFlags);

    final updatedState = _withInlineNotesCommentator(
      currentState.copyWith(
        content: event.content,
        contentVersion: currentState.contentVersion + 1,
        loadedLineFlags: _loadedContentFlags,
      ),
    );
    // אחרי שסרקנו את התוכן המלא, אין יותר טעם בסריקה נוספת על הרחבות
    // טווח עתידיות — או שכבר הוסף 'הערות' ל-availableCommentators (ואז
    // early-return שומר עלינו), או שאין הערות בכלל בספר.
    _inlineNotesFullScanDone = true;
    emit(updatedState);
    _markLoadedContentRange(
      currentState.book,
      0,
      event.content.isEmpty ? 0 : event.content.length - 1,
      totalLines: event.content.length,
    );
  }

  List<String> _contentWithAppliedRange(BookContentRange range) {
    final content = ChunkedList<String>.filled(
      _fullContentLength(range),
      '',
    ).edit();
    final first = max(0, range.startLine);
    final end = min(content.length, range.startLine + range.lines.length);
    if (first < end) {
      content.setRange(first, end, range.lines, first - range.startLine);
    }
    return content.build();
  }

  List<bool> _loadedContentFlagsWithAppliedRange(BookContentRange range) {
    final loadedFlags = ChunkedList<bool>.filled(
      _fullContentLength(range),
      false,
    ).edit();
    final first = max(0, range.startLine);
    final end = min(loadedFlags.length, range.startLine + range.lines.length);
    if (first < end) {
      loadedFlags.fillRange(first, end, true);
    }
    return loadedFlags.build();
  }

}
