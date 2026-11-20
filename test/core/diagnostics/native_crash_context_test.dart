import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/app_context_snapshot.dart';
import 'package:otzaria/core/diagnostics/native_crash_context.dart';
import 'package:otzaria/core/diagnostics/native_diagnostics_bridge.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

import '../../helpers/memory_settings_cache.dart';

class _StubTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _StubTabsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _StubNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.library));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('encodeContext', () {
    test('שורה אחת, בלי שבירת תו באמצע', () {
      expect(
        utf8.decode(NativeDiagnosticsBridge.encodeContext('א\r\nב')),
        'א ב',
      );
      final long = NativeDiagnosticsBridge.encodeContext('א' * 200);
      expect(long.length, lessThanOrEqualTo(254));
      expect(long.length.isEven, isTrue);
      expect(utf8.decode(long), 'א' * (long.length ~/ 2));
    });
  });

  group('describeShortAppContext', () {
    test('ספר: מסך, סוג וכותרת', () async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      final tab = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
      addTearDown(tab.dispose);
      expect(
        describeShortAppContext(
          screen: Screen.reading,
          tabs: TabsState(tabs: [tab], currentTabIndex: 0),
        ),
        'screen=reading; tabs=1; tab=TextBookTab; title=בראשית',
      );
    });

    test('חיפוש: השאילתה לא נכנסת', () {
      final tab = SearchingTab(SearchingTab.titleForQuery('פרטי'), null);
      addTearDown(tab.dispose);
      expect(
        describeShortAppContext(
          screen: Screen.search,
          tabs: TabsState(tabs: [tab], currentTabIndex: 0),
        ),
        'screen=search; tabs=1; tab=SearchingTab',
      );
    });
  });

  testWidgets(
    'מעדכן רק כשההקשר משתנה, כולל הדלקת הנגישות',
    semanticsEnabled: false,
    (
      tester,
    ) async {
      addTearDown(AccessibilityDiagnostics.resetForTest);
      final navigation = _StubNavigationBloc();
      final tabs = _StubTabsBloc(const TabsState(tabs: [], currentTabIndex: 0));
      addTearDown(navigation.close);
      addTearDown(tabs.close);
      final sent = <String>[];

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<NavigationBloc>.value(value: navigation),
            BlocProvider<TabsBloc>.value(value: tabs),
          ],
          child: NativeCrashContextScope(
            sink: sent.add,
            child: const SizedBox(),
          ),
        ),
      );
      expect(sent, ['screen=library; tabs=0']);

      tabs.emit(const TabsState(tabs: [], currentTabIndex: 0));
      await tester.pump();
      expect(sent, hasLength(1));

      navigation.emit(const NavigationState(currentScreen: Screen.settings));
      await tester.pump();
      expect(sent.last, 'screen=settings; tabs=0');

      expect(AccessibilityDiagnostics.describe()['semanticsEnabled'], isFalse);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(sent.last, matches(r'^semantics=on@\d+ms; screen=settings'));
      final described = AccessibilityDiagnostics.describe();
      expect(described['semanticsEnabled'], isTrue);
      expect(described['semanticsFirstEnabledAtMs'], isA<int>());
      semantics.dispose();
    },
  );
}
