import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/centered_text_search_session.dart';
import 'package:pdfrx/pdfrx.dart';

const _pageText = 'שלום עולם';

/// כל תו ברוחב 10, בשורה שבין y=90 ל-y=100 בקואורדינטות העמוד.
final _charRects = [
  for (var i = 0; i < _pageText.length; i++)
    PdfRect(i * 10.0, 100, i * 10.0 + 10, 90),
];

class _FakePage extends Fake implements PdfPage {
  @override
  int get pageNumber => 1;

  @override
  bool get isLoaded => true;
}

class _FakeDocument extends Fake implements PdfDocument {
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();

  @override
  List<PdfPage> get pages => [_FakePage()];
}

/// מתעד את הניווט: לאיזו נקודה חושבה המטריצה, ואיזו פעולה רצה קודם.
class _RecordingController extends PdfViewerController {
  final _document = _FakeDocument();
  final actions = <String>[];
  Offset? centeredOn;

  @override
  bool get isReady => true;

  @override
  PdfDocument get document => _document;

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => task(_document);

  // העמוד מתחיל בראש המסמך; ציר ה-y של PDF הפוך לזה של התצוגה.
  @override
  Rect calcRectForRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
  }) => Rect.fromLTRB(rect.left, 100 - rect.top, rect.right, 100 - rect.bottom);

  @override
  Matrix4 calcMatrixFor(Offset position, {double? zoom, Size? viewSize}) {
    centeredOn = position;
    return Matrix4.identity();
  }

  @override
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) async => actions.add('goTo');

  @override
  Future<void> ensureVisible(
    Rect rect, {
    Duration duration = const Duration(milliseconds: 200),
    double margin = 0,
  }) async => actions.add('ensureVisible');

  @override
  void setCurrentPageNumber(int pageNumber) {}

  @override
  void invalidate() {}
}

class _Session extends CenteredTextSearchSession {
  _Session(super.controller);

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => PdfPageText(
    pageNumber: pageNumber,
    fullText: _pageText,
    charRects: _charRects,
    fragments: const [],
  );
}

void main() {
  test('מעבר להתאמה ממרכז את מרכז המלבן שלה בתצוגה', () async {
    final controller = _RecordingController();
    final session = _Session(controller);
    addTearDown(session.dispose);

    session.startTextSearch(
      'עולם',
      goToFirstMatch: false,
      searchImmediately: true,
    );
    for (var i = 0; i < 5 && session.matches.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.matches, hasLength(1));

    expect(await session.goToMatchOfIndex(0), 0);

    // "עולם" הוא תווים 5–8: x בין 50 ל-90, y בין 0 ל-10.
    expect(controller.centeredOn, const Offset(70, 5));
    expect(controller.actions, ['goTo', 'ensureVisible']);
    expect(session.currentIndex, 0);
  });
}
