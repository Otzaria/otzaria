import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/parallel_editions_action.dart';
import 'package:otzaria/library/services/parallel_editions_service.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/controls/bar_split_button.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

void main() {
  final companion = ParallelEdition(
    book: PdfBook(title: 'ברכות', path: '/books/ברכות.pdf'),
    isCompanion: true,
  );
  final external = ParallelEdition(
    book: PdfBook(title: 'ברכות וילנא', path: '/books/וילנא.pdf'),
    isCompanion: false,
    label: 'דפוס וילנא',
  );
  final opened = <ParallelEdition>[];

  ActionButtonData build(List<ParallelEdition> editions) =>
      buildParallelEditionsAction(
        editions: editions,
        compact: false,
        companionIcon: FluentIcons.document_pdf_24_regular,
        companionTooltip: 'פתח בתצוגת PDF',
        companionMenuSuffix: 'מהדורה מודפסת (אוצריא)',
        onOpen: opened.add,
      );

  setUp(opened.clear);

  test('מהדורה אחת: כפתור רגיל שפותח אותה', () {
    final action = build([companion]);

    expect(action.widget, isA<BarButton>());
    expect(action.tooltip, 'פתח בתצוגת PDF');
    expect(action.icon, FluentIcons.document_pdf_24_regular);
    expect(action.actionId, ToolbarActionId.parallelEdition);
    action.onPressed!();
    expect(opened, [companion]);
  });

  test('מהדורה ראשית שאינה מובנית מקבלת את הכיתוב הכללי', () {
    expect(build([external]).tooltip, 'פתח מהדורה מקבילה');
  });

  test('כמה מהדורות: כפתור מפוצל שמפרט את כולן', () {
    final action = build([companion, external]);

    expect(action.widget, isA<BarSplitButton<int>>());
    final menu = action.submenuItems!.skip(1).toList();
    expect(
      [for (final item in menu) item.tooltip],
      [
        'ברכות — מהדורה מודפסת (אוצריא)',
        'דפוס וילנא',
      ],
    );
    expect(
      [for (final item in menu) item.icon],
      [
        FluentIcons.document_pdf_24_regular,
        OtzariaIcons.book_24_regular,
      ],
    );
    menu.last.onPressed!();
    expect(opened, [external]);
  });
}
