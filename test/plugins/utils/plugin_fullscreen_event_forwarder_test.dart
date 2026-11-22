import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/plugins/utils/plugin_fullscreen_event_forwarder.dart';

/// `ui.fullscreenChanged`: כל שינוי של מצב המסך המלא של החלון (כפתור, F11,
/// Escape, יציאה אוטומטית במעבר מסך) נשלח לתוספים עם המצב החדש.
void main() {
  late WindowFullscreenCubit cubit;
  final events =
      <({String topic, Map<String, dynamic> payload, int? viewId})>[];

  setUp(() {
    events.clear();
    cubit = WindowFullscreenCubit(initial: false, persist: (_) async {});
  });

  tearDown(() => cubit.close());

  Future<void> pumpForwarder(WidgetTester tester) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: BlocProvider<WindowFullscreenCubit>.value(
        value: cubit,
        child: PluginFullscreenEventForwarder(
          dispatch: (topic, payload, {viewId}) async =>
              events.add((topic: topic, payload: payload, viewId: viewId)),
          child: const SizedBox(),
        ),
      ),
    ),
  );

  testWidgets('בבנייה הראשונה אין אירוע', (tester) async {
    await pumpForwarder(tester);
    expect(events, isEmpty);
  });

  testWidgets('כניסה ויציאה שולחות ui.fullscreenChanged עם המצב החדש', (
    tester,
  ) async {
    await pumpForwarder(tester);

    await cubit.set(true);
    await tester.pump();
    await cubit.set(false);
    await tester.pump();

    expect(events.map((e) => e.topic), everyElement('ui.fullscreenChanged'));
    expect(events.map((e) => e.payload), [
      {'fullscreen': true},
      {'fullscreen': false},
    ]);
  });

  testWidgets('מצב זהה לנוכחי אינו שולח אירוע כפול', (tester) async {
    await pumpForwarder(tester);

    await cubit.set(true);
    await cubit.set(true);
    await tester.pump();

    expect(events, hasLength(1));
  });

  testWidgets('האירוע מכוון לחלון שבו הווידג׳ט נמצא', (tester) async {
    await pumpForwarder(tester);

    await cubit.set(true);
    await tester.pump();

    expect(events.single.viewId, tester.view.viewId);
  });
}
