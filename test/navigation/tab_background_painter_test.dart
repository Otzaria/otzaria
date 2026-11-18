import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/tab_background_painter.dart';

void main() {
  group('TabBackgroundPainter.shouldRepaint', () {
    const base = TabBackgroundPainter(
      Colors.blue,
      bodyHeight: 40,
    );

    test('does not repaint when all paint inputs are unchanged', () {
      const next = TabBackgroundPainter(
        Colors.blue,
        bodyHeight: 40,
      );

      expect(base.shouldRepaint(next), isFalse);
    });

    test('repaints when fill, body height, border, or flare changes', () {
      expect(
        base.shouldRepaint(
          const TabBackgroundPainter(Colors.red, bodyHeight: 40),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const TabBackgroundPainter(Colors.blue, bodyHeight: 41),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const TabBackgroundPainter(
            Colors.blue,
            bodyHeight: 40,
            borderColor: Colors.white,
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const TabBackgroundPainter(
            Colors.blue,
            bodyHeight: 40,
            flareOutline: Colors.white,
          ),
        ),
        isTrue,
      );
    });
  });
}
