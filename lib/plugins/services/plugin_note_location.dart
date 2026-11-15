import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/services/plugin_highlight_anchor_service.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// המילים שתוסף ביקש לעגן אליהן הערה. [fromSource] — [text] ו-[offset] נלקחו
/// מטקסט השורה בלי HTML (שכבת source), ולא מהתצוגה.
typedef PluginNoteAnchor = ({
  String text,
  int? offset,
  int? occurrence,
  bool fromSource,
});

const int _maxAnchorTextLength = 10000;

/// קורא את `range` או `text` (+ `occurrence`) של `notes.add`. בלי שניהם —
/// null, והערה על השורה כולה. [loadLine] מחזיר את השורה הגולמית, או null
/// כשאינה קיימת.
Future<PluginNoteAnchor?> parsePluginNoteAnchor(
  Map<String, dynamic> args,
  Future<String?> Function() loadLine,
) async {
  final range = args['range'];
  final text = args['text'];
  final occurrence = args['occurrence'];
  if (range != null && text != null) {
    throw Exception('error.invalid_params: pass either range or text');
  }
  if (occurrence != null &&
      (occurrence is! int || occurrence < 0 || text == null)) {
    throw Exception(
      'error.invalid_params: occurrence must be a non-negative integer with text',
    );
  }
  if (text != null) {
    if (text is! String ||
        text.trim().isEmpty ||
        text.length > _maxAnchorTextLength) {
      throw Exception('error.invalid_params: text must be a non-empty string');
    }
    return (
      text: text,
      offset: null,
      occurrence: occurrence as int?,
      fromSource: false,
    );
  }
  if (range == null) return null;
  if (range is! Map) {
    throw Exception('error.invalid_params: range must be an object');
  }
  final PluginTextRangeAnchor anchor;
  try {
    anchor = PluginTextRangeAnchor.fromJson(Map<String, dynamic>.from(range));
  } on FormatException catch (error) {
    throw Exception('error.invalid_params: ${error.message}');
  }
  if (anchor.layer != 'source') {
    throw Exception('error.invalid_params: range must use the source layer');
  }
  final line = await loadLine();
  if (line == null) {
    throw Exception('error.invalid_params: lineNumber is outside the book');
  }
  final resolved = const PluginHighlightAnchorService().resolve(
    anchor: anchor,
    sourceText: TextRendererService.stripHtml(line),
  );
  final found = resolved.range;
  if (resolved.status != 'active' || found == null) {
    throw Exception('error.not_found: range was not found in the line');
  }
  return (
    text: found.exactText,
    offset: found.start.utf16,
    occurrence: null,
    fromSource: true,
  );
}

/// המיקום שתוסף ביקש להערה ב-`notes.add` או ב-`notes.setLocation`.
typedef PluginNoteLocation = ({
  PersonalNoteScope scope,
  int? lineNumber,
  int? endLineNumber,
  PluginNoteAnchor? anchor,
});

/// קורא `scope`, `lineNumber`, `endLineNumber` ואת העוגן ([parsePluginNoteAnchor]).
/// בלי `scope` הסוג נקבע לפי מה שהועבר. [loadLines] — שורות הספר, ונקרא רק
/// כשצריך לבדוק מיקום או עוגן.
Future<PluginNoteLocation> parsePluginNoteLocation(
  Map<String, dynamic> args,
  Future<List<String>> Function() loadLines,
) async {
  final scopeName = args['scope'];
  final lineNumber = args['lineNumber'];
  final endLineNumber = args['endLineNumber'];
  final hasAnchor = args['range'] != null || args['text'] != null;
  if (scopeName != null &&
      !PersonalNoteScope.values.any((scope) => scope.name == scopeName)) {
    throw Exception(
      "error.invalid_params: scope must be 'book', 'lines' or 'words'",
    );
  }
  if (scopeName == PersonalNoteScope.book.name) {
    if (lineNumber != null || endLineNumber != null || hasAnchor) {
      throw Exception(
        'error.invalid_params: a book note takes no lineNumber, '
        'endLineNumber, range or text',
      );
    }
    return (
      scope: PersonalNoteScope.book,
      lineNumber: null,
      endLineNumber: null,
      anchor: null,
    );
  }
  if (lineNumber is! int || lineNumber < 1) {
    throw Exception('error.invalid_params: lineNumber must be 1 or more');
  }
  if (endLineNumber != null &&
      (endLineNumber is! int || endLineNumber < lineNumber || hasAnchor)) {
    throw Exception(
      'error.invalid_params: endLineNumber must be at least lineNumber, '
      'without range or text',
    );
  }
  final wantsWords = scopeName == PersonalNoteScope.words.name;
  if (wantsWords && !hasAnchor) {
    throw Exception('error.invalid_params: words need range or text');
  }
  if (scopeName == PersonalNoteScope.lines.name && hasAnchor) {
    throw Exception('error.invalid_params: lines take no range or text');
  }
  List<String>? lines;
  if (endLineNumber != null || hasAnchor || scopeName != null) {
    lines = await loadLines();
    final last = (endLineNumber as int?) ?? lineNumber;
    if (lines.isNotEmpty && last > lines.length) {
      throw Exception('error.invalid_params: lineNumber is outside the book');
    }
  }
  final anchor = await parsePluginNoteAnchor(
    args,
    () async => lines != null && lineNumber <= lines.length
        ? lines[lineNumber - 1]
        : null,
  );
  return (
    scope: anchor != null ? PersonalNoteScope.words : PersonalNoteScope.lines,
    lineNumber: lineNumber,
    endLineNumber: endLineNumber as int?,
    anchor: anchor,
  );
}

/// הערה כפי שהיא נמסרת לתוספים.
Map<String, dynamic> pluginNoteJson(PersonalNote note) => {
  'id': note.id,
  'bookId': note.bookId,
  'scope': note.scope.name,
  'status': note.status.name,
  'lineNumber': note.lineNumber,
  'endLineNumber': note.endLineNumber,
  'anchorText': note.anchorText,
  'content': note.content,
  'contentPlain': note.contentPlain,
  'createdAt': note.createdAt.toIso8601String(),
  'updatedAt': note.updatedAt.toIso8601String(),
};
