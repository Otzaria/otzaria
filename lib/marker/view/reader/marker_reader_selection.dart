import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_selection.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/text_book/view/selection/keyboard_selection_settings.dart';

/// שורות שמעבר לקצה המחושב, לשינויי תצוגה שמאריכים את הטקסט (שם השם).
const int _marginLines = 2;

/// תגיות, ניקוד וטעמים: כשהם מוסתרים הטקסט המוצג קצר בהרבה מהמקור.
final RegExp _hidden = RegExp('<[^>]*>|[\u0591-\u05C7]');

/// מסמן את הבחירה בלי תפריט, מהקיצור או מהסרגל. [lineIndex] ו-[column] הם
/// השורה והעמודה שבהן הבחירה מתחילה, כפי שהמסך שומר אותן.
Future<void> markReaderSelection({
  required BuildContext context,
  required TextBookLoaded state,
  required String? selectedText,
  required int? lineIndex,
  required int? column,
  MarkerColor? color,
}) async {
  final text = selectedText ?? '';
  if (text.trim().isEmpty || lineIndex == null || lineIndex < 0) {
    UiSnack.show(MarkerMessages.noSelection);
    return;
  }
  final draft = await markerReaderSelectionDraft(
    context: context,
    state: state,
    selectedText: text,
    lineIndex: lineIndex,
    column: column,
  );
  await MarkerActions.instance.mark(
    draft,
    color ?? MarkerSettings.instance.palette.defaultColor,
  );
}

/// טיוטה מהבחירה כפי שהמסך שומר אותה, או null כשאין בחירה או שאי אפשר
/// לעגן אותה. שורות שעוד לא נטענו נקראות מהספר.
Future<MarkerDraft?> markerReaderSelectionDraft({
  required BuildContext context,
  required TextBookLoaded state,
  required String? selectedText,
  required int? lineIndex,
  required int? column,
}) async {
  final text = selectedText ?? '';
  if (text.trim().isEmpty || lineIndex == null || lineIndex < 0) return null;
  final repository = context.read<TextBookBloc>().repository;
  final settings = keyboardSelectionRenderSettings(
    state,
    context.read<SettingsBloc>().state,
  );
  MarkerDraft? draft;
  try {
    // בקריאה רציפה שורות מחוברות ברווח, ולכן מספר מעברי השורה אינו מספר
    // השורות. השורות שבין הראשונה לאחרונה נבחרו במלואן, כך שאורך הבחירה
    // חוסם מלמעלה את השורה האחרונה.
    final guess = lineIndex + text.split('\n').length - 1;
    var lines = state.content;
    var last = _lastLineFor(lines, lineIndex, text.length);
    if (lines.length <= lineIndex ||
        lines
            .sublist(lineIndex, (last + 1).clamp(lineIndex, lines.length))
            .any((line) => line.isEmpty)) {
      lines = await splitContentLines(
        await repository.getBookContent(state.book),
      );
      last = _lastLineFor(lines, lineIndex, text.length);
    }
    if (guess >= lines.length) return null;
    MarkerDraft? draftUntil(int lastLine) => markerDraftFromSelection(
      state: state,
      lines: lines,
      paragraphIndex: lineIndex,
      selectedText: text,
      anchor: (
        lineStart: lineIndex,
        lineEnd: lastLine,
        startColumn: column,
        pointerColumn: null,
      ),
      settings: settings,
    );
    draft = draftUntil(guess);
    if (draft == null && last > guess) {
      final wider = draftUntil(last);
      if (wider?.segments.first.sectionIndex == lineIndex) draft = wider;
    }
  } catch (error, stackTrace) {
    debugPrint('Marker: reading the selection failed: $error');
    debugPrintStack(stackTrace: stackTrace, maxFrames: 5);
  }
  return draft;
}

/// שורות המקור [first] ו-[last] של הספר, גם כשהן עוד לא נטענו לתצוגה.
Future<({String first, String last})?> markerSourceLines(
  BuildContext context,
  TextBookLoaded state,
  int first,
  int last,
) async {
  var lines = state.content;
  bool missing(int i) => i < 0 || i >= lines.length || lines[i].isEmpty;
  if (missing(first) || missing(last)) {
    final repository = context.read<TextBookBloc>().repository;
    lines = await splitContentLines(
      await repository.getBookContent(state.book),
    );
    if (missing(first) || missing(last)) return null;
  }
  return (first: lines[first], last: lines[last]);
}

/// השורה האחרונה שבחירה באורך [length] מ-[first] יכולה להגיע אליה.
int _lastLineFor(List<String> lines, int first, int length) {
  var covered = 0;
  for (var i = first + 1; i < lines.length; i++) {
    if (covered > length) {
      return (i + _marginLines).clamp(first, lines.length - 1);
    }
    covered += lines[i].replaceAll(_hidden, '').length;
  }
  return lines.length - 1;
}
