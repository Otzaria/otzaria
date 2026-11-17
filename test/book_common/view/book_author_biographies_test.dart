import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/book_author_biographies.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';

void main() {
  testWidgets('shows Hebrew years and opens the selected author by ID', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAuthorBiographies(
            biographies: const [
              Biography(id: 'a', name: 'מחבר א'),
              Biography(
                id: 'sh-383',
                name: 'רבי משה בן נחמן',
                born: LifeEvent(hebrew: 'ד׳תתקנ״ד', gregorian: '1194'),
                died: LifeEvent(hebrew: 'ה׳ל׳', gregorian: '1270'),
                works: [BiographyWork(title: 'תורת האדם')],
              ),
            ],
            openBiography: (id) => opened = id,
          ),
        ),
      ),
    );
    expect(find.text('ד׳תתקנ״ד – ה׳ל׳'), findsOneWidget);
    expect(find.textContaining('1194'), findsNothing);
    expect(find.text(BiographiesBundle.authorCredit), findsOneWidget);
    expect(find.text('תורת האדם'), findsNothing);

    await tester.tap(find.text('רבי משה בן נחמן'));
    await tester.pumpAndSettle();
    expect(find.text('תורת האדם'), findsOneWidget);
    await tester.tap(find.text('לביוגרפיה המלאה'));
    expect(opened, 'sh-383');
  });
}
