import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') ||
          name.contains('remap') ||
          name.contains('flush')) {
        return Future<void>.value();
      }
      if (name.contains('loadTabs')) return <OpenedTab>[];
      if (name.contains('loadCurrentTabIndex')) return 0;
    }
    return null;
  }
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  ToolTab pluginTab(String id, String title) =>
      ToolTab(toolId: id, title: title, instanceId: 'inst-$id');

  TextBookTab textTab() =>
      TextBookTab(book: TextBook(title: 'ברכות'), index: 0);

  group('unsavedPluginTabs', () {
    late PluginUnsavedChangesRegistry registry;

    setUp(() => registry = PluginUnsavedChangesRegistry.forTesting());

    test('מחזיר רק כרטיסיות תוסף שסימנו שינויים, עם ההודעה שלהן', () {
      final dirty = pluginTab('p.editor', 'עורך');
      final clean = pluginTab('p.other', 'אחר');
      registry.set(
        (pluginId: 'p.editor', instanceId: 'inst-p.editor'),
        hasChanges: true,
        message: 'הטיוטה תאבד',
      );

      final result = unsavedPluginTabs([
        textTab(),
        clean,
        dirty,
      ], registry: registry);

      expect(result, hasLength(1));
      expect(result.single.tab, same(dirty));
      expect(result.single.message, 'הטיוטה תאבד');
    });

    test('כלי מובנה אינו נחשב תוסף גם אם מזהה המופע רשום', () {
      final builtIn = ToolTab(
        toolId: 'builtin.calendar',
        title: 'לוח שנה',
        instanceId: 'x',
      );
      registry.set(
        (pluginId: 'builtin.calendar', instanceId: 'x'),
        hasChanges: true,
      );
      expect(unsavedPluginTabs([builtIn], registry: registry), isEmpty);
    });

    test('מוצא חלונית תוסף בתוך כרטיסיה מפוצלת', () {
      final dirty = pluginTab('p.editor', 'עורך');
      registry.set(
        (pluginId: 'p.editor', instanceId: 'inst-p.editor'),
        hasChanges: true,
      );
      final combined = CombinedTab(rightTab: textTab(), leftTab: dirty);

      final result = unsavedPluginTabs([combined], registry: registry);
      expect(result.single.tab, same(dirty));
      expect(result.single.message, isNull);
    });
  });

  test('unsavedChangesDialogContent — שורה לכרטיסיה ואחריה ההודעה', () {
    final content = unsavedChangesDialogContent([
      (tab: pluginTab('a', 'עורך'), message: 'הטיוטה תאבד'),
      (tab: pluginTab('b', 'טבלה'), message: null),
    ]);
    expect(
      content,
      'ב"עורך" יש שינויים שלא נשמרו.\nהטיוטה תאבד\nב"טבלה" יש שינויים שלא נשמרו.',
    );
  });

  group('confirmCloseTabs', () {
    final key = (pluginId: 'p.editor', instanceId: 'inst-p.editor');

    tearDown(() => PluginUnsavedChangesRegistry.instance.removeInstance(key));

    Future<Future<bool>> pump(WidgetTester tester, ToolTab tab) async {
      late Future<bool> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = confirmCloseTabs(context, [tab]),
              child: const Text('close'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('בלי שינויים — מאשר מיד בלי דיאלוג', (tester) async {
      final result = await pump(tester, pluginTab('p.editor', 'עורך'));
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
      expect(await result, isTrue);
    });

    testWidgets('עם שינויים — הדיאלוג מציג את ההודעה וביטול מחזיר false', (
      tester,
    ) async {
      PluginUnsavedChangesRegistry.instance.set(
        key,
        hasChanges: true,
        message: 'הטיוטה תאבד',
      );
      final result = await pump(tester, pluginTab('p.editor', 'עורך'));

      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      expect(find.textContaining('הטיוטה תאבד'), findsOneWidget);

      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('"סגור בכל זאת" מחזיר true', (tester) async {
      PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
      final result = await pump(tester, pluginTab('p.editor', 'עורך'));

      await tester.tap(find.text(unsavedChangesCloseAnyway));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  });

  group('confirmAppCloseWithUnsavedChanges', () {
    final key = (pluginId: 'p.editor', instanceId: 'inst-p.editor');
    late TabsBloc tabsBloc;

    setUp(() => tabsBloc = TabsBloc(repository: _FakeTabsRepository()));
    tearDown(() async {
      PluginUnsavedChangesRegistry.instance.removeInstance(key);
      await tabsBloc.close();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(
        BlocProvider<TabsBloc>.value(
          value: tabsBloc,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      tabsBloc.add(ReplaceAllTabs([pluginTab('p.editor', 'עורך')], 0));
      await tester.pump();
    }

    testWidgets('בלי שינויים — מאשר בלי דיאלוג', (tester) async {
      await pumpApp(tester);
      expect(await confirmAppCloseWithUnsavedChanges(), isTrue);
      await tester.pump();
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
    });

    testWidgets('שני מאזינים מקבלים את אותה תשובה מדיאלוג אחד', (
      tester,
    ) async {
      await pumpApp(tester);
      PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);

      final first = confirmAppCloseWithUnsavedChanges();
      final second = confirmAppCloseWithUnsavedChanges();
      await tester.pumpAndSettle();

      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      expect(find.text(unsavedChangesAppCloseSubtitle), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(await first, isFalse);
      expect(await second, isFalse);

      // אחרי שהדיאלוג נסגר, קריאה חדשה פותחת דיאלוג חדש.
      final third = confirmAppCloseWithUnsavedChanges();
      await tester.pumpAndSettle();
      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      await tester.tap(find.text(unsavedChangesCloseAnyway));
      await tester.pumpAndSettle();
      expect(await third, isTrue);
    });
  });
}
