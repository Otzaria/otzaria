import 'package:otzaria/book_common/range_edit/text_range_edit.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

/// עריכת המיקום של הערת טקסט: סוג המיקום ([scope]) והטווח בשורות הספר.
/// מילים — בשורה אחת; שורות — שורה אחת או יותר; ספר — בלי מיקום.
class NoteLocationEdit {
  NoteLocationEdit._(this.range, this._savedScope, this._unlocated)
    : _scope = _savedScope;

  /// [rawLines] — שורות הספר כפי שנשמרו (HTML). הערה בלי מיקום נפתחת
  /// בשורה [fallbackLine] (1-based). null לספר בלי שורות.
  static NoteLocationEdit? of(
    PersonalNote note,
    List<String> rawLines, {
    int? fallbackLine,
  }) {
    if (rawLines.isEmpty) return null;
    String source(int index) => text_utils.stripHtmlIfNeeded(rawLines[index]);
    TextRangeEdit lines(int first, int last) => TextRangeEdit(
      paragraphCount: rawLines.length,
      paragraphAt: source,
      start: (paragraph: first, offset: 0),
      end: (paragraph: last, offset: 0),
      unit: TextRangeUnit.paragraphs,
      crossParagraphs: false,
    );

    if (note.hasLocation) {
      final first = (note.lineNumber! - 1).clamp(0, rawLines.length - 1);
      final last = (note.lastLineNumber! - 1).clamp(first, rawLines.length - 1);
      if (note.isWordAnchored) {
        final text = source(first);
        final found = locateAnchor(
          rawLine: text,
          anchorText: note.anchorText!,
          prefix: note.anchorPrefix,
          suffix: note.anchorSuffix,
          plainText: true,
        );
        if (found != null) {
          return NoteLocationEdit._(
            TextRangeEdit(
              paragraphCount: rawLines.length,
              paragraphAt: source,
              start: (paragraph: first, offset: found.start),
              end: (paragraph: first, offset: found.end),
              crossParagraphs: false,
            ),
            PersonalNoteScope.words,
            false,
          );
        }
      }
      return NoteLocationEdit._(
        lines(first, last),
        PersonalNoteScope.lines,
        false,
      );
    }
    final line =
        ((note.isBookNote ? null : note.lastKnownLineNumber) ??
            fallbackLine ??
            1) -
        1;
    final index = line.clamp(0, rawLines.length - 1);
    return NoteLocationEdit._(
      lines(index, index),
      note.isBookNote ? PersonalNoteScope.book : PersonalNoteScope.lines,
      !note.isBookNote,
    );
  }

  final TextRangeEdit range;
  final PersonalNoteScope _savedScope;

  /// הערה שאיבדה את מיקומה: גם שמירה בלי שינוי ממקמת אותה.
  final bool _unlocated;

  PersonalNoteScope _scope;

  PersonalNoteScope get scope => _scope;

  set scope(PersonalNoteScope value) {
    _scope = value;
    if (value == PersonalNoteScope.words) range.unit = TextRangeUnit.words;
    if (value == PersonalNoteScope.lines) {
      range.unit = TextRangeUnit.paragraphs;
    }
  }

  /// יש מה לשמור: שינוי, או הערה שאיבדה את מיקומה.
  bool get changed => _unlocated || differs;

  /// המיקום שונה ממה שנשמר.
  bool get differs =>
      _scope != _savedScope ||
      (_scope != PersonalNoteScope.book && range.changed);

  /// חזרה למה שנשמר.
  void reset() {
    range.reset();
    _scope = _savedScope;
  }
}
