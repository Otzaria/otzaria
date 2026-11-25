import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/dialogs/hidden_books_picker_dialog.dart';

void main() {
  for (final touch in [false, true]) {
    testWidgets(
      'בבורר ההסתרה אפשר לקרוא כותרת ונתיב שנחתכו ב${touch ? 'מגע' : 'עכבר'}',
      (tester) async {
        tester.view.physicalSize = const Size(700, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final prefix = List.filled(12, 'קטגוריה ארוכה').join(' ');
        final title = List.filled(12, 'ספר בשם ארוך').join(' ');
        final library = Library(categories: []);
        for (final suffix in ['א', 'ב']) {
          final category = Category(
            title: '$prefix $suffix',
            description: '',
            shortDescription: '',
            order: 0,
            subCategories: [],
            books: [],
            parent: library,
          );
          category.books.add(TextBook(title: title, category: category));
          library.subCategories.add(category);
        }
        final path = library.subCategories.last.path;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: TextButton(
                    onPressed: () => showHiddenBooksPickerDialog(
                      context: context,
                      library: library,
                      hidden: HiddenLibrarySelection(
                        bookKeys: const {},
                        categoryPaths: const {},
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final label = find.text(path);
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isTrue,
        );
        final row = find.byWidget(
          tester.widget<CheckboxListTile>(
            find.ancestor(of: label, matching: find.byType(CheckboxListTile)),
          ),
        );
        final height = tester.getSize(row).height;
        // הכותרת זהה בשני הספרים; הנתיב שנחתך מבדיל ביניהם.
        final full = '$title\n$path';
        expect(find.byTooltip(full), findsOneWidget);
        if (touch) {
          await tester.longPress(label);
        } else {
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer();
          await mouse.moveTo(tester.getCenter(label));
        }
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text(full), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(full))
              .didExceedMaxLines,
          isFalse,
        );
        expect(tester.getSize(row).height, height);
      },
    );
  }
}
