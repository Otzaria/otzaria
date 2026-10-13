import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/freeze_context_reporter.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';

const _channel = MethodChannel('otzaria/process_control');
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> sent;
  late _FakeTabsBloc tabsBloc;
  late _FakeNavigationBloc navigationBloc;

  setUp(() {
    sent = [];
    tabsBloc = _FakeTabsBloc(const TabsState(tabs: [], currentTabIndex: 0));
    navigationBloc = _FakeNavigationBloc(
      const NavigationState(currentScreen: Screen.library),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'setFreezeContext') sent.add(call.arguments);
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await tabsBloc.close();
    await navigationBloc.close();
  });

  Future<void> pumpReporter(WidgetTester tester) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
        ],
        child: FreezeContextReporter(
          describe: () => {
            'screen': navigationBloc.state.currentScreen.name,
            'tabs': tabsBloc.state.tabs.length,
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }

  testWidgets('שולח את ההקשר בהתחלה', (tester) async {
    await pumpReporter(tester);
    await tester.pump();

    expect(sent, ['screen: library, tabs: 0']);
  }, variant: _windows);

  testWidgets('שולח שוב כשההקשר משתנה', (tester) async {
    await pumpReporter(tester);
    await tester.pump();

    navigationBloc.emit(const NavigationState(currentScreen: Screen.reading));
    await tester.pump();

    expect(sent, ['screen: library, tabs: 0', 'screen: reading, tabs: 0']);
  }, variant: _windows);

  testWidgets('אינו שולח שוב כשהמחרוזת זהה', (tester) async {
    await pumpReporter(tester);
    await tester.pump();

    // שינוי מצב שאינו משנה את התיאור.
    navigationBloc.emit(
      const NavigationState(
        currentScreen: Screen.library,
        hasCheckedLibrary: true,
      ),
    );
    tabsBloc.emit(const TabsState(tabs: [], currentTabIndex: 1));
    await tester.pump();

    expect(sent, ['screen: library, tabs: 0']);
  }, variant: _windows);
}

class _FakeTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _FakeNavigationBloc(super.initialState);

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
