import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria_ocr/otzaria_ocr.dart';
import 'package:pdfrx/pdfrx.dart';

/// בקר מצב לסימון OCR.
/// אוצריא פותח את המצב מתוך כפתור הסרגל, וה-[PdfOcrOverlay] מאזין ומציג
/// שכבת הסימון. הניתוק אוטומטי בסיום ה-OCR.
class PdfOcrSelectionController extends ChangeNotifier {
  bool _active = false;
  bool get active => _active;

  void enter() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void exit() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}

/// סינגלטון של ה-OcrService - שומר על isolate ארוך-חיים בין קריאות.
class _OcrSingleton {
  _OcrSingleton._();
  static final _OcrSingleton instance = _OcrSingleton._();
  final OcrService service = createOcrService();
}

/// פונקציית callback לעיצוב הטקסט לפני ההעתקה ללוח.
/// מקבלת את הטקסט שזוהה ואת מספר העמוד, מחזירה את הטקסט הסופי להעתקה.
typedef PdfOcrClipboardFormatter = Future<String> Function(
  String recognizedText,
  int pageNumber,
);

/// סף מינימום בפיקסלים לסימון תקין (מתחת לזה זה קליק בטעות).
const double _kMinSelectionPx = 8.0;

/// DPI לרינדור: 2x של 72-DPI ≈ 144 DPI. איזון בין דיוק זיהוי ל-latency.
const double _kRenderScale = 2.0;

/// שכבת drag-to-OCR מעל מציג ה-PDF.
///
/// כשמצב הסימון פעיל, השכבה תופסת את האירועים, מציירת מלבן סימון, ובסיום
/// הגרירה: מרנדרת את האזור בעמוד הרלוונטי ב-DPI גבוה, מעבירה ל-OCR,
/// ומעתיקה את הטקסט ללוח. אין UI נפרד לתוצאה.
///
/// בפלטפורמות שאין בהן backend אמיתי (לא-Windows, או Windows ללא החבילה
/// הפרטית), כל ה-UI עובד עד שלב ה-`recognizeImage` - שם זורקת חריגה
/// שמוצגת כ-UiSnack. זה מאפשר למפתחים על כל פלטפורמה לשפר את ה-UI.
class PdfOcrOverlay extends StatefulWidget {
  const PdfOcrOverlay({
    super.key,
    required this.controller,
    required this.viewportSize,
    required this.selectionController,
    this.formatForClipboard,
  });

  final PdfViewerController controller;
  final Size viewportSize;
  final PdfOcrSelectionController selectionController;

  /// אם מסופק, נקרא לפני ההעתקה ללוח כדי לעצב את הטקסט
  /// (למשל הוספת שם הספר וכותרת לפי הגדרות המשתמש).
  final PdfOcrClipboardFormatter? formatForClipboard;

  @override
  State<PdfOcrOverlay> createState() => _PdfOcrOverlayState();
}

class _PdfOcrOverlayState extends State<PdfOcrOverlay> {
  Offset? _start;
  Offset? _current;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    widget.selectionController.addListener(_onModeChanged);
  }

  @override
  void dispose() {
    widget.selectionController.removeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged() {
    if (!widget.selectionController.active && mounted) {
      setState(() {
        _start = null;
        _current = null;
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_processing) return;
    setState(() {
      _start = details.localPosition;
      _current = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_processing || _start == null) return;
    setState(() {
      _current = details.localPosition;
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_processing) return;
    final start = _start;
    final current = _current;
    if (start == null || current == null) return;

    final rect = Rect.fromPoints(start, current);
    if (rect.width < _kMinSelectionPx || rect.height < _kMinSelectionPx) {
      setState(() {
        _start = null;
        _current = null;
      });
      return;
    }

    setState(() => _processing = true);
    try {
      await _processSelection(rect);
    } on OcrUnsupportedPlatformException {
      UiSnack.showError('זיהוי OCR לא זמין בבנייה הזו של אוצריא');
    } on OcrMissingBundledFilesException {
      UiSnack.showError('קבצי ה-OCR חסרים בבנייה. פנו לתחזוקה.');
    } on OcrFailureException catch (e) {
      UiSnack.showError('שגיאה בזיהוי: ${e.message}');
    } catch (e) {
      UiSnack.showError('שגיאה בזיהוי: $e');
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _start = null;
          _current = null;
        });
      }
      widget.selectionController.exit();
    }
  }

  /// מבצע את כל ה-flow: viewport rect → page rect → render → OCR → clipboard.
  Future<void> _processSelection(Rect viewportRect) async {
    final controller = widget.controller;
    if (!controller.isReady) {
      throw const OcrFailureException('המסמך לא מוכן');
    }

    // 1. מצא את העמוד שמכיל את הסימון, וחשב את המלבן בקואורדינטות הדף.
    final pageHit = _hitTestPage(controller, viewportRect);
    if (pageHit == null) {
      UiSnack.showError('יש לסמן מעל עמוד ה-PDF');
      return;
    }
    final pageNumber = pageHit.pageNumber;
    final pageLocalRect = pageHit.pageLocalRect;

    // 2. רנדר את האזור הספציפי ב-DPI גבוה.
    final pages = controller.document.pages;
    final page = pages[pageNumber - 1];
    final fullW = page.width * _kRenderScale;
    final fullH = page.height * _kRenderScale;
    final renderX = (pageLocalRect.left * _kRenderScale).round();
    final renderY = (pageLocalRect.top * _kRenderScale).round();
    final renderW = (pageLocalRect.width * _kRenderScale).round();
    final renderH = (pageLocalRect.height * _kRenderScale).round();

    if (renderW <= 0 || renderH <= 0) {
      UiSnack.showError('האזור שסומן קטן מדי');
      return;
    }

    final pdfImage = await page.render(
      x: renderX,
      y: renderY,
      width: renderW,
      height: renderH,
      fullWidth: fullW,
      fullHeight: fullH,
      backgroundColor: 0xFFFFFFFF,
    );
    if (pdfImage == null) {
      throw const OcrFailureException('הרינדור נכשל');
    }

    Uint8List pngBytes;
    try {
      final uiImage = await pdfImage.createImage();
      try {
        final byteData =
            await uiImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw const OcrFailureException('המרת PNG נכשלה');
        }
        pngBytes = byteData.buffer.asUint8List();
      } finally {
        uiImage.dispose();
      }
    } finally {
      pdfImage.dispose();
    }

    // 3. שולח ל-OCR (יכול לזרוק חריגה אם אין backend אמיתי).
    final ocr = _OcrSingleton.instance.service;
    final result = await ocr.recognizeImage(pngBytes);

    if (result.isEmpty) {
      UiSnack.show('לא זוהה טקסט באזור שסומן');
      return;
    }

    // 4. עיצוב + העתקה ללוח + הודעה.
    final formatter = widget.formatForClipboard;
    final clipboardText = formatter != null
        ? await formatter(result.text, pageNumber)
        : result.text;

    await Clipboard.setData(ClipboardData(text: clipboardText));
    final preview = clipboardText.length > 40
        ? '${clipboardText.substring(0, 40)}...'
        : clipboardText;
    UiSnack.show('הועתק ללוח: $preview');
  }

  /// מאתר את העמוד שמכיל את מרכז [viewportRect], ומחזיר את החיתוך
  /// המתאים בקואורדינטות מקומיות של אותו עמוד (לפני קנה-המידה של הרינדור).
  _PageHit? _hitTestPage(PdfViewerController controller, Rect viewportRect) {
    final layout = controller.layout;
    final matrix = controller.value;
    final pageLayouts = layout.pageLayouts;
    final inverted = Matrix4.tryInvert(matrix);
    if (inverted == null) return null;

    // ה-rect של הסימון בקואורדינטות המסמך (לפני transformation).
    final docRect = MatrixUtils.transformRect(inverted, viewportRect);

    for (int i = 0; i < pageLayouts.length; i++) {
      final pageRect = pageLayouts[i];
      final intersection = pageRect.intersect(docRect);
      if (intersection.width <= 0 || intersection.height <= 0) continue;

      // המרה ל-coords מקומיים של העמוד (0,0 בפינה הימנית/שמאלית עליונה).
      final localRect = Rect.fromLTWH(
        intersection.left - pageRect.left,
        intersection.top - pageRect.top,
        intersection.width,
        intersection.height,
      );
      return _PageHit(pageNumber: i + 1, pageLocalRect: localRect);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.selectionController.active) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: MouseRegion(
        cursor:
            _processing ? SystemMouseCursors.wait : SystemMouseCursors.precise,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Stack(
            children: [
              // רקע כהה-למחצה כדי לסמן שמצב הסימון פעיל.
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: scheme.scrim.withValues(alpha: 0.12),
                  ),
                ),
              ),
              // מלבן הסימון - אם יש.
              if (_start != null && _current != null)
                Positioned.fromRect(
                  rect: Rect.fromPoints(_start!, _current!),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        border: Border.all(
                          color: scheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              // אינדיקטור עיבוד.
              if (_processing)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'מזהה טקסט...',
                                textDirection: TextDirection.rtl,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHit {
  const _PageHit({required this.pageNumber, required this.pageLocalRect});
  final int pageNumber;
  final Rect pageLocalRect;
}
