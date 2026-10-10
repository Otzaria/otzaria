import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_common/utils/commentators_menu.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataRoot;
  final book = PdfBook(title: 'בדיקת מפרשים', path: '/commentators.pdf');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    dataRoot = await Directory.systemTemp.createTemp('pdf_commentators_');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
  });

  tearDown(() async {
    await PerBookSettings.settle();
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });

  for (final initial in [
    {'רש"י'},
    {'רש"י', 'רמב"ן'},
  ]) {
    test('לחיצות חוזרות על מפרש פעיל פותחות בלי לשמור $initial', () async {
      final active = Set<String>.of(initial);
      await PdfBookPerBookSettings(
        activeCommentators: active.toList(),
        zoom: 2,
      ).save(book);
      final file = (await Directory(
        '${dataRoot.path}/per_book_settings',
      ).list().toList()).whereType<File>().single;
      final original = await file.readAsString();
      await file.setLastModified(DateTime.utc(2000));
      final modified = await file.lastModified();
      var saves = 0;
      var opens = 0;
      final entries = buildCommentatorsContextMenuChildren(
        availableCommentators: const ['רש"י', 'רמב"ן'],
        commentatorGroups: const [],
        getActiveCommentators: () => active,
        onCommentatorsChanged: (updated, {required isAdding}) =>
            applyPdfCommentatorSelection(
              activeCommentators: active,
              updated: updated.toSet(),
              onChanged: () {
                saves++;
                unawaited(
                  PdfBookPerBookSettings(
                    activeCommentators: active.toList(),
                  ).save(book),
                );
              },
              onOpenPane: () => opens++,
            ),
      );
      final entry = entries.firstWhere((entry) => entry.label == 'רש"י');

      for (var i = 0; i < 3; i++) {
        entry.onTap!();
        await PerBookSettings.settle();
        expect(await file.readAsString(), original);
        expect(await file.lastModified(), modified);
      }
      expect(saves, 0);
      expect(opens, 3);
      expect(active, initial);
    });
  }

  test('בחירה חדשה נשמרת פעם אחת ונפתחת גם בלחיצה חוזרת', () async {
    final active = {'רמב"ן'};
    var saves = 0;
    var opens = 0;
    final entries = buildCommentatorsContextMenuChildren(
      availableCommentators: const ['רש"י', 'רמב"ן'],
      commentatorGroups: const [],
      getActiveCommentators: () => active,
      onCommentatorsChanged: (updated, {required isAdding}) =>
          applyPdfCommentatorSelection(
            activeCommentators: active,
            updated: updated.toSet(),
            onChanged: () {
              saves++;
              unawaited(
                PdfBookPerBookSettings(
                  activeCommentators: active.toList(),
                ).save(book),
              );
            },
            onOpenPane: () => opens++,
          ),
    );
    final entry = entries.firstWhere((entry) => entry.label == 'רש"י');
    entry.onTap!();
    await PerBookSettings.settle();
    expect(
      (await PdfBookPerBookSettings.load(book))?.activeCommentators,
      unorderedEquals(['רמב"ן', 'רש"י']),
    );
    entry.onTap!();
    await PerBookSettings.settle();
    expect(saves, 1);
    expect(opens, 2);
    expect(active, {'רמב"ן', 'רש"י'});
  });

  test('השוואת בחירה אינה תלויה בסדר הקבוצה', () {
    var saves = 0;
    var opens = 0;
    final active = {'רש"י', 'רמב"ן'};
    applyPdfCommentatorSelection(
      activeCommentators: active,
      updated: {'רמב"ן', 'רש"י'},
      onChanged: () => saves++,
      onOpenPane: () => opens++,
    );
    expect(saves, 0);
    expect(opens, 1);
    expect(active.toList(), ['רש"י', 'רמב"ן']);
  });

  testWidgets('ברירות מחדל שנטענו אחרי פתיחת התפריט נשמרות בלחיצה', (
    tester,
  ) async {
    final tab = PdfBookTab(
      book: PdfBook(
        title: 'ספר אישי',
        path: '/defaults.pdf',
        source: BookSource.user,
      ),
      pageNumber: 1,
    );
    final key = GlobalKey<AppContextMenuRegionState>();
    late StateSetter rebuild;
    var menuBuilds = 0;
    var saves = 0;
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Center(
                  child: AppContextMenuRegion(
                    key: key,
                    menuBuilder: (_, _) {
                      menuBuilds++;
                      return [
                        AppContextMenuEntry(
                          label: 'מפרשים',
                          children: buildCommentatorsContextMenuChildren(
                            getActiveCommentators: () => tab.activeCommentators,
                            availableCommentators: const ['רש"י', 'רמב"ן'],
                            commentatorGroups: const [],
                            onCommentatorsChanged:
                                (updated, {required isAdding}) =>
                                    applyPdfCommentatorSelection(
                                      activeCommentators:
                                          tab.activeCommentators,
                                      updated: updated.toSet(),
                                      onChanged: () => saves++,
                                      onOpenPane: () => opens++,
                                    ),
                          ),
                        ),
                      ];
                    },
                    child: const SizedBox(
                      width: 300,
                      height: 300,
                      child: Text('גוף הספר'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await key.currentState!.showMenu();
    await tester.pumpAndSettle();
    final defaults = await DefaultCommentators.resolveAutoSelection(
      tab.book,
      availableCommentators: const ['רש"י', 'רמב"ן'],
      savedSelection: null,
    );
    expect(defaults, ['רש"י', 'רמב"ן']);
    rebuild(() => tab.activeCommentators.addAll(defaults!));
    await tester.pumpAndSettle();
    expect(menuBuilds, 1);
    await tester.tap(find.text('מפרשים'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('רמב"ן'));
    await tester.pumpAndSettle();
    expect(tab.activeCommentators, {'רש"י', 'רמב"ן'});
    expect(saves, 0);
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final label in ['הצג את כל ראשונים', 'הצג את כל המפרשים']) {
    for (final initiallyActive in [false, true]) {
      test('$label משתמש בבחירה שהתעדכנה לאחר הפתיחה ($initiallyActive)', () {
        bool? adding;
        var saves = 0;
        var opens = 0;
        final active = {
          'מלבי"ם',
          if (initiallyActive) ...['רש"י', 'רמב"ן'],
        };
        final entries = buildCommentatorsContextMenuChildren(
          getActiveCommentators: () => active,
          availableCommentators: const ['רש"י', 'רמב"ן'],
          commentatorGroups: const [
            CommentatorGroup(title: 'ראשונים', commentators: ['רש"י', 'רמב"ן']),
          ],
          showAllLabel: 'הצג את כל המפרשים',
          onCommentatorsChanged: (updated, {required isAdding}) {
            adding = isAdding;
            applyPdfCommentatorSelection(
              activeCommentators: active,
              updated: updated.toSet(),
              onChanged: () => saves++,
              onOpenPane: () => opens++,
            );
          },
        );
        if (initiallyActive) {
          active.remove('רש"י');
        } else {
          active.addAll(['רש"י', 'רמב"ן']);
        }
        entries.firstWhere((entry) => entry.label == label).onTap!();
        expect(active, {
          'מלבי"ם',
          if (initiallyActive) ...['רש"י', 'רמב"ן'],
        });
        expect(adding, initiallyActive);
        expect(saves, 1);
        expect(opens, 1);
      });
    }
  }
}
