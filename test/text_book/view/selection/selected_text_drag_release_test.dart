import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:super_native_extensions/src/native/context.dart';
import 'package:otzaria/text_book/view/selection/selected_text_drag.dart';

const _content = (
  plainText: 'drag text',
  htmlText: '<b>drag text</b>',
  fontFamily: 'Arial',
  fontSize: 16.0,
);

void main() {
  final mock = MockMessageChannelContext();
  setContextOverride(mock);
  final messages = <String>[];
  Completer<int>? registration;
  Completer<int>? nativeStart;
  Completer<bool>? needsImage;
  var preparations = 0;

  setUp(() {
    messages.clear();
    registration = null;
    nativeStart = null;
    needsImage = null;
    preparations = 0;
    mock.registerMockMethodCallHandler('DataProviderManager', (call) {
      messages.add(call.method);
      if (call.method == 'registerDataProvider') {
        return registration?.future ?? 1;
      }
      return null;
    });
    mock.registerMockMethodCallHandler('DragManager', (call) {
      messages.add(call.method);
      if (call.method == 'needsCombinedDragImage') {
        return needsImage?.future ?? false;
      }
      if (call.method == 'startDrag') return nativeStart?.future ?? 1;
      return null;
    });
  });

  Future<TestGesture> startDrag(
    WidgetTester tester,
    Future<SelectedTextDragContent?> content, {
    bool crossThreshold = true,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.irondash.engine_context'),
      (_) async => 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: SelectedTextDragRegion(
            selectedText: () => 'drag text',
            captureContent: (_) => () {
              preparations++;
              return content;
            },
            child: const SelectionArea(child: Text('drag text')),
          ),
        ),
      ),
    );
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea))
        .selectableRegion
        .selectAll();
    await tester.pump();
    final gesture = await tester.startGesture(
      const Offset(20, 8),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(crossThreshold ? 20 : 4, 0));
    await tester.pump();
    expect(preparations, crossThreshold ? 1 : 0);
    return gesture;
  }

  Future<void> finishImages(WidgetTester tester) async {
    // Image conversion runs outside the tester's fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets('click below threshold does not build export content', (
    tester,
  ) async {
    final gesture = await startDrag(
      tester,
      Future.value(_content),
      crossThreshold: false,
    );
    await gesture.up();
    await tester.pump();
    expect(messages, isEmpty);
  });

  for (final cancel in [false, true]) {
    testWidgets('release/cancel while preparing (cancel=$cancel)', (
      tester,
    ) async {
      final prepare = Completer<SelectedTextDragContent?>();
      final gesture = await startDrag(tester, prepare.future);
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
      prepare.complete(_content);
      await finishImages(tester);
      expect(messages, isEmpty);
    });
  }

  for (final dispose in [false, true]) {
    testWidgets('release/dispose while registering (dispose=$dispose)', (
      tester,
    ) async {
      registration = Completer<int>();
      final gesture = await startDrag(tester, Future.value(_content));
      expect(messages, ['registerDataProvider']);
      if (dispose) {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        await gesture.up();
        await tester.pump();
      }
      registration!.complete(1);
      await finishImages(tester);
      if (dispose) await gesture.up();
      expect(messages, ['registerDataProvider', 'unregisterDataProvider']);
    });
  }

  for (final dispose in [false, true]) {
    testWidgets(
      'cancel survives internal serialization awaits (dispose=$dispose)',
      (tester) async {
        needsImage = Completer<bool>();
        final gesture = await startDrag(tester, Future.value(_content));
        await finishImages(tester);
        expect(messages, contains('needsCombinedDragImage'));
        TestGesture? next;
        if (dispose) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          await gesture.up();
          await tester.pump();
          next = await tester.startGesture(
            const Offset(20, 8),
            kind: PointerDeviceKind.mouse,
          );
        }
        needsImage!.complete(false);
        await finishImages(tester);
        expect(messages, isNot(contains('startDrag')));
        expect(messages.last, 'unregisterDataProvider');
        if (dispose) await gesture.up();
        await next?.up();
        await tester.pump();
      },
    );
  }

  for (final dispose in [false, true]) {
    testWidgets(
      'failed native start after release disposes resources (dispose=$dispose)',
      (tester) async {
        nativeStart = Completer<int>();
        final gesture = await startDrag(tester, Future.value(_content));
        await finishImages(tester);
        expect(messages, contains('startDrag'));
        if (dispose) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          await gesture.up();
          await tester.pump();
        }
        nativeStart!.completeError(PlatformException(code: 'start_failed'));
        await finishImages(tester);
        expect(messages.last, 'unregisterDataProvider');
        expect(
          messages.where((method) => method == 'unregisterDataProvider'),
          hasLength(1),
        );
        if (dispose) await gesture.up();
        nativeStart = null;
        messages.clear();
        preparations = 0;
        final retry = await startDrag(tester, Future.value(_content));
        await finishImages(tester);
        expect(messages, contains('startDrag'));
        await mock.invokeMethod('DragManager', 'dragSessionDidEnd', {
          'sessionId': 1,
          'dropOperation': 'userCancelled',
        });
        await mock.invokeMethod('DragManager', 'releaseDataProvider', 1);
        await retry.up();
        await tester.pump();
      },
    );
  }

  testWidgets('held pointer starts native copy and releases native ownership', (
    tester,
  ) async {
    needsImage = Completer<bool>()..complete(true);
    final gesture = await startDrag(tester, Future.value(_content));
    await finishImages(tester);
    expect(messages, contains('startDrag'));
    expect(messages, isNot(contains('unregisterDataProvider')));
    await mock.invokeMethod('DragManager', 'dragSessionDidEnd', {
      'sessionId': 1,
      'dropOperation': 'userCancelled',
    });
    await mock.invokeMethod('DragManager', 'releaseDataProvider', 1);
    expect(messages.last, 'unregisterDataProvider');
    await gesture.up();
    await tester.pump();
  });
}
