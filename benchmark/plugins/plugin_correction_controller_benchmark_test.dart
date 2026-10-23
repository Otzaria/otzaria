import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';

void main() {
  testWidgets('מדידת buildTextSpan על 50K תווים', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final controller = PluginCorrectionController(
      '<b>${'אב' * 12500}</b><i>${'גד' * 12500}</i>',
    );
    addTearDown(controller.dispose);
    final context = tester.element(find.byType(SizedBox));
    const style = TextStyle(fontSize: 20);
    for (final composing in [
      TextRange.empty,
      const TextRange(start: 1, end: 49999),
    ]) {
      controller.value = controller.value.copyWith(composing: composing);
      TextSpan build() => controller.buildTextSpan(
        context: context,
        style: style,
        withComposing: true,
      );
      for (var warmup = 0; warmup < 10; warmup++) {
        build();
      }
      for (var sample = 1; sample <= 2; sample++) {
        final watch = Stopwatch()..start();
        for (var frame = 0; frame < 40; frame++) {
          build();
        }
        watch.stop();
        debugPrint(
          'CORRECTION_BENCH composing=${composing.isValid} sample=$sample '
          'usPerBuild=${watch.elapsedMicroseconds / 40}',
        );
      }
      expect(build().toPlainText(), controller.text);
    }
  });

  testWidgets('מדידת בניית העיצוב הראשונה מול רצף רווחים שהקורא מכווץ', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    const style = TextStyle(fontSize: 20);
    for (final length in [5000, 10000, 19000]) {
      final inputs = {
        'spaces': 'א${' ' * length}ב',
        'plain': 'א${'ב' * length}ג',
      };
      for (final MapEntry(key: kind, value: raw) in inputs.entries) {
        for (var sample = 1; sample <= 3; sample++) {
          final controller = PluginCorrectionController(raw);
          final watch = Stopwatch()..start();
          final span = controller.buildTextSpan(
            context: context,
            style: style,
            withComposing: false,
          );
          watch.stop();
          expect(span.toPlainText(), controller.text);
          controller.dispose();
          debugPrint(
            'CORRECTION_STYLE_BENCH kind=$kind length=$length sample=$sample '
            'ms=${watch.elapsedMicroseconds / 1000}',
          );
        }
      }
    }
  });
}
