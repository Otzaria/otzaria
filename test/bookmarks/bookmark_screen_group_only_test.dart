import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../helpers/memory_settings_cache.dart';

class _StubBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _StubBookmarkBloc(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// LQ-11: כשיש רק סימניה מרוכזת, המצב הריק לא אומר "אין סימניות".
void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<void> pump(WidgetTester tester, BookmarkState state) async {
    final bloc = _StubBookmarkBloc(state);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<BookmarkBloc>.value(
          value: bloc,
          child: const Scaffold(body: BookmarkView()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('רק סימניה מרוכזת: "אין סימניות לספר בודד"', (tester) async {
    await pump(
      tester,
      BookmarkState(
        bookmarks: const [],
        groups: [
          BookmarkGroup(
            name: 'סדר יומי',
            items: [
              Bookmark(
                ref: 'ברכות ב, א',
                book: TextBook(title: 'ברכות'),
                index: 0,
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.text('סדר יומי'), findsOneWidget);
    expect(find.text('אין סימניות לספר בודד'), findsOneWidget);
    expect(find.text('אין סימניות'), findsNothing);
  });

  testWidgets('בלי סימניות בכלל: "אין סימניות"', (tester) async {
    await pump(tester, BookmarkState(bookmarks: const []));

    expect(find.text('אין סימניות'), findsOneWidget);
  });
}
