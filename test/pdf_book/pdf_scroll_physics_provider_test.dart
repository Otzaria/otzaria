import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_scroll_physics_provider.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';
import 'package:pdfrx/pdfrx.dart';

class _RecordingDelegate implements PdfViewerScrollInteractionDelegate {
  int stops = 0;
  final pans = <Offset>[];

  @override
  void init(PdfViewerController controller, TickerProvider vsync) {}

  @override
  void dispose() {}

  @override
  void stop() => stops++;

  @override
  void pan(Offset delta, PdfViewerLayoutMetrics layoutMetrics) =>
      pans.add(delta);

  @override
  void zoom(
    double scale,
    Offset focalPoint,
    PdfViewerLayoutMetrics layoutMetrics,
  ) {}
}

class _RecordingProvider extends PdfViewerScrollInteractionDelegateProvider {
  final created = <_RecordingDelegate>[];

  @override
  PdfViewerScrollInteractionDelegate create() {
    final delegate = _RecordingDelegate();
    created.add(delegate);
    return delegate;
  }

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}

void main() {
  group('StoppablePdfScrollPhysicsProvider', () {
    test('stop לפני create אינו נופל', () {
      final provider = StoppablePdfScrollPhysicsProvider(
        inner: _RecordingProvider(),
      );
      expect(provider.stop, returnsNormally);
    });

    test('stop מועבר ל-delegate האחרון שנוצר', () {
      final inner = _RecordingProvider();
      final provider = StoppablePdfScrollPhysicsProvider(inner: inner);

      provider.create();
      provider.stop();
      expect(inner.created.single.stops, 1);

      // pdfrx יוצר delegate חדש בהחלפת provider — העצירה עוקבת אחרי החדש.
      provider.create();
      provider.stop();
      expect(inner.created.first.stops, 1);
      expect(inner.created.last.stops, 1);
    });

    // גלילת החיצים עוברת באותה החלקה כמו הגלגלת, ולא ב-goTo שמתאפס כל צעד.
    test('pan מועבר ל-delegate, ולפני create אינו נופל', () {
      final inner = _RecordingProvider();
      final provider = StoppablePdfScrollPhysicsProvider(inner: inner);
      expect(() => provider.pan(const Offset(0, -10)), returnsNormally);

      provider.create();
      provider.pan(const Offset(0, -100));
      provider.pan(const Offset(0, -8));
      expect(inner.created.single.pans, const [Offset(0, -100), Offset(0, -8)]);
    });

    test('zoomTo מחזיר false כל עוד אין צפיין פעיל', () {
      final inner = _RecordingProvider();
      final provider = StoppablePdfScrollPhysicsProvider(inner: inner);
      expect(provider.zoomTo(2, Offset.zero), isFalse);
      provider.create();
      expect(provider.zoomTo(2, Offset.zero), isFalse);
      expect(inner.created.single.stops, 0);
    });

    test('ברירת המחדל עוטפת את ה-delegate הפיזיקלי של pdfrx', () {
      final provider = StoppablePdfScrollPhysicsProvider();
      expect(provider.create(), isA<PdfViewerScrollInteractionDelegate>());
    });

    // מעבר בין ספר טקסט ל-PDF באותה תוכנה חייב להרגיש באותה מהירות,
    // ולכן שני אזורי הקריאה נגזרים מאותו קבוע.
    test('קצב גלילת ה-PDF נגזר מקצב גלילת הטקסט', () {
      final inner =
          StoppablePdfScrollPhysicsProvider().inner
              as PdfViewerScrollInteractionDelegateProviderPhysics;

      expect(inner.panFriction, SmoothWheelScroll.decayRatePerMs * 1000);
      expect(
        inner.panFriction,
        isNot(
          const PdfViewerScrollInteractionDelegateProviderPhysics().panFriction,
        ),
        reason: 'ברירת המחדל של pdfrx איטית כמעט כפול מגלילת הטקסט',
      );
    });

    test('שוויון לפי זהות — אותו מופע לא גורם ליצירת delegate חדש', () {
      final a = StoppablePdfScrollPhysicsProvider();
      final b = StoppablePdfScrollPhysicsProvider();
      expect(a == a, isTrue);
      expect(a == b, isFalse);
    });
  });
}
