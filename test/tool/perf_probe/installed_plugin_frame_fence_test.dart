import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/installed_plugin_completion.dart';

class _ControlledScheduler extends RenderingFlutterBinding {
  @override
  void scheduleFrame() {}

  @override
  void drawFrame() {}
}

class _SceneView extends Fake implements ui.FlutterView {
  var submissions = 0;

  @override
  int get viewId => 0;

  @override
  void render(ui.Scene scene, {ui.Size? size}) => submissions++;
}

class _PaintView extends RenderView {
  _PaintView(ui.FlutterView view)
    : super(
        view: view,
        configuration: const ViewConfiguration(
          logicalConstraints: BoxConstraints.tightFor(width: 10, height: 10),
          physicalConstraints: BoxConstraints.tightFor(width: 10, height: 10),
        ),
      );

  var paints = 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
    super.paint(context, offset);
  }
}

void main() {
  final binding = _ControlledScheduler();
  for (final phase in SchedulerPhase.values) {
    for (final currentEnd
        in phase == SchedulerPhase.postFrameCallbacks
            ? ['absent', 'pending', 'completed']
            : ['absent']) {
      test(
        'the fence submits a fresh scene after $phase ($currentEnd endOfFrame)',
        () async {
          var frameNumber = 40;
          var active = true;
          final view = _SceneView();
          final root = _PaintView(view)..automaticSystemUiAdjustment = false;
          final pipeline = PipelineOwner()..rootNode = root;
          root.prepareInitialFrame();
          int? submissionsAtRepaint;
          Future<int>? pending;
          var completed = false;
          void requestFence() {
            pending = submitInstalledPluginFrameFence(
              binding,
              repaintViews: () {
                submissionsAtRepaint = view.submissions;
                root.markNeedsPaint();
              },
              frameNumber: () => frameNumber,
            );
            unawaited(pending!.then((_) => completed = true));
          }

          binding.addPersistentFrameCallback((_) {
            if (!active) return;
            if (phase == SchedulerPhase.persistentCallbacks &&
                pending == null) {
              requestFence();
            }
            pipeline.flushLayout();
            pipeline.flushCompositingBits();
            pipeline.flushPaint();
            root.compositeFrame();
          });
          Future<void> draw() async {
            frameNumber++;
            binding.handleBeginFrame(Duration(milliseconds: frameNumber * 16));
            await Future<void>.value();
            binding.handleDrawFrame();
            await Future<void>.delayed(Duration.zero);
          }

          try {
            switch (phase) {
              case SchedulerPhase.idle:
                requestFence();
              case SchedulerPhase.transientCallbacks:
                binding.scheduleFrameCallback((_) => requestFence());
              case SchedulerPhase.midFrameMicrotasks:
                binding.scheduleFrameCallback(
                  (_) => scheduleMicrotask(requestFence),
                );
              case SchedulerPhase.persistentCallbacks:
                break;
              case SchedulerPhase.postFrameCallbacks:
                binding.scheduleFrameCallback((_) {
                  if (currentEnd == 'completed') unawaited(binding.endOfFrame);
                  binding.addPostFrameCallback((_) => requestFence());
                  if (currentEnd == 'pending') unawaited(binding.endOfFrame);
                });
            }
            if (phase != SchedulerPhase.idle) {
              await draw();
              expect(completed, isFalse);
              expect(root.paints, 1);
              expect(submissionsAtRepaint, 1);
            } else {
              expect(submissionsAtRepaint, 0);
            }
            await draw();
            expect(await pending, frameNumber);
            expect(view.submissions, phase == SchedulerPhase.idle ? 1 : 2);
            expect(root.paints, phase == SchedulerPhase.idle ? 1 : 2);
            expect(completed, isTrue);
          } finally {
            active = false;
            pipeline.rootNode = null;
            root.dispose();
            pipeline.dispose();
          }
        },
      );
    }
  }
}
