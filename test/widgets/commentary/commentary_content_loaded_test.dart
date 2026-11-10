import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

import '../../test_helpers/stub_settings_bloc.dart';

class _Provider extends Fake implements LibraryProvider {
  @override
  Future<String> getLinkContent(Link link) async =>
      List.filled(40, 'מילה ארוכה בפירוש').join(' ');
}

void main() {
  final manager = LibraryProviderManager.instance;
  tearDown(manager.resetForTesting);
  // ספק הבדיקה אינו מסד; בלי הקיצור איתורו נכשל, וכשל בטעינת ההערות מדווח.
  setUp(
    () => BookNotesRepository.instance
      ..clear()
      ..debugIsDatabaseBook = (title, {categoryId, fileType}) async => false,
  );
  tearDown(
    () => BookNotesRepository.instance
      ..debugIsDatabaseBook = null
      ..clear(),
  );

  // פריט מפרש שנבנה מחדש בגלילה למעלה: אם הוא מתחיל בשלד טעינה קצר וגדל
  // אחריו, הוא דוחף את הרשימה חזרה למטה (issue #1588).
  testWidgets('מפרש שתוכנו כבר נטען נבנה מיד בגובהו הסופי', (tester) async {
    manager.seedMappingsForTesting(
      mapping: <BookCompositeKey, LibraryProvider>{},
      providers: <LibraryProvider>[_Provider()],
    );
    final link = Link(
      heRef: 'רש"י על סוכה, מד., א',
      index1: 1,
      path2: 'רש"י על סוכה',
      index2: 9101,
      connectionType: LinkTypes.commentary,
    );
    await link.content;
    final settings = StubSettingsBloc();
    addTearDown(settings.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: Scaffold(
            body: SingleChildScrollView(
              child: CommentaryContent(
                link: link,
                fontSize: 18,
                openBookCallback: (_) {},
                displayProfile: TextDisplayProfile.defaults,
              ),
            ),
          ),
        ),
      ),
    );
    final firstFrame = tester.getSize(find.byType(CommentaryContent)).height;
    await tester.pumpAndSettle();

    expect(
      firstFrame,
      tester.getSize(find.byType(CommentaryContent)).height,
    );
  });
}
