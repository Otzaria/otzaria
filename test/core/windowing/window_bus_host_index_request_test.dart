import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_bus_host.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

/// כל חלון רשאי **ליזום** אינדוקס, והמארח הוא שמבצע: Tantivy נועל את
/// ה-writer בלעדית, והחלון הראשון מחזיק את הנעילה לכל חיי התהליך.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockLibraryBloc libraryBloc;
  late _MockIndexingBloc indexingBloc;
  final library = Library(categories: []);

  setUpAll(() => registerFallbackValue(ClearIndex()));

  setUp(() {
    MultiWindowService.debugSupportedOverride = true;
    WindowBus.namespace = 'otzaria.test.bushost.index';
    libraryBloc = _MockLibraryBloc();
    indexingBloc = _MockIndexingBloc();
    when(() => libraryBloc.state).thenReturn(
      LibraryState.initial().copyWith(library: library),
    );
  });

  tearDown(() {
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    WindowBus.namespace = 'otzaria.window';
    MultiWindowService.debugSupportedOverride = null;
    WindowRole.isSecondary = false;
  });

  Future<Object?> sendIndexRequest(WidgetTester tester, String op) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<IndexingBloc>.value(value: indexingBloc),
        ],
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    return WindowBus.instance.onRequest!({
      'type': MultiWindowService.requestIndex,
      'op': op,
    });
  }

  testWidgets('בקשת אינדוקס מלא נכנסת מפעילה StartIndexing', (tester) async {
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpAll,
    );
    expect(accepted, isTrue);
    verify(() => indexingBloc.add(StartIndexing(library))).called(1);
  });

  testWidgets('בקשת איפוס נכנסת מפעילה ClearIndex', (tester) async {
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpClear,
    );
    expect(accepted, isTrue);
    verify(() => indexingBloc.add(any(that: isA<ClearIndex>()))).called(1);
  });

  testWidgets('פעולה לא מוכרת נדחית', (tester) async {
    final accepted = await sendIndexRequest(tester, 'הפעלה שאינה קיימת');
    expect(accepted, isFalse);
    verifyNever(() => indexingBloc.add(any()));
  });

  // המבצע הוא המארח בלבד — חלון משני שקיבל בקשה היה שולח אותה לעצמו.
  testWidgets('חלון משני דוחה בקשת אינדוקס נכנסת', (tester) async {
    WindowRole.isSecondary = true;
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpAll,
    );
    expect(accepted, isFalse);
    verifyNever(() => indexingBloc.add(any()));
  });
}
