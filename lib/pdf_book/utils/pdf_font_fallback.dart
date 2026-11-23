import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:otzaria/pdf_book/utils/pdf_font_load_coordinator.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:pdfrx/pdfrx.dart';

/// פתיחת PDF כשלגופנים שאינם מוטמעים בקובץ נרשם גופן אמיתי.
///
/// pdfrx אינו פונה לגופני המערכת בעצמו: גופן לא מוטמע שלא נרשם מוחלף בגופן
/// פנימי בלי עברית, והאותיות נעלמות גם מהתצוגה וגם מהטקסט (חיפוש, אינדוקס).
class PdfFontFallback {
  PdfFontFallback._();

  static const String bundledFallbackAsset = 'fonts/Tinos-Regular.ttf';

  static final PdfFontManager _manager = PdfFontManager.platform(
    resolvers: [
      const _SystemFamilyResolver(),
      const _BundledFontResolver(),
    ],
  );
  static final _fontLoads = PdfFontLoadCoordinator(
    load: _manager.loadMissingFonts,
  );

  /// פותח את [filePath]. גופן שחסר נקבע בזמן הטעינה, ולכן אחרי רישום
  /// גופנים חדשים המסמך נפתח מחדש. הרישום גלובלי — פתיחה חוזרת קורית פעם אחת.
  static Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool useProgressiveLoading = false,
  }) async {
    Future<PdfDocument> open() => PdfDocument.openFile(
      filePath,
      passwordProvider: passwordProvider,
      useProgressiveLoading: useProgressiveLoading,
    );

    final document = await open();
    final missing = await _reportedMissingFonts(document);
    if (missing.isEmpty) return document;

    final bool fontsLoaded;
    try {
      fontsLoaded = await _fontLoads.loadMissingFonts(missing);
    } catch (_) {
      return document;
    }
    if (!fontsLoaded) return document;

    // ה-worker של pdfrx חייב להשתחרר מהמסמך לפני פתיחתו מחדש.
    await document.dispose();
    return open();
  }

  /// הפניה למסמך עבור [PdfViewer], עם אותו מפתח שמשמש [PdfDocumentRefFile].
  static PdfDocumentRef documentRef(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool useProgressiveLoading = true,
  }) {
    return PdfDocumentRefByLoader(
      (_) async {
        await pdfrxFlutterInitialize();
        return openFile(
          filePath,
          passwordProvider: passwordProvider,
          useProgressiveLoading: useProgressiveLoading,
        );
      },
      key: PdfDocumentRefKey(filePath),
    );
  }

  static Future<List<PdfFontQuery>> _reportedMissingFonts(
    PdfDocument document,
  ) async {
    final missing = <PdfFontQuery>[];
    final subscription = document.events.listen((event) {
      if (event is PdfDocumentMissingFontsEvent) {
        missing.addAll(event.missingFonts);
      }
    });
    // האירוע נשמר ב-replay של המסמך ונמסר למאזין חדש באסינכרוניות.
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return missing;
  }

  /// שם המשפחה ששמור בשם גופן של PDF: בלי קידומת subset ובלי סיומת סגנון.
  static String familyFromPdfFace(String face) {
    final plus = face.indexOf('+');
    final base = plus >= 0 ? face.substring(plus + 1) : face;
    final styleStart = base.indexOf(RegExp('[-,]'));
    return (styleStart > 0 ? base.substring(0, styleStart) : base).trim();
  }
}

/// גופן מערכת שמשפחתו תואמת לשם שבקובץ (David, Narkisim וכו').
class _SystemFamilyResolver implements PdfFontResolver {
  const _SystemFamilyResolver();

  @override
  Future<PdfFontResolution?> resolve(
    PdfFontQuery query,
    PdfFontResolveContext context,
  ) async {
    await AppFonts.warmUpSystemFontsCache();
    final faces = AppFonts.pluginSystemFamilyFacesByCompactName(
      PdfFontFallback.familyFromPdfFace(query.face),
    );
    if (faces == null) return null;
    final isBold =
        query.weight >= 600 || query.face.toLowerCase().contains('bold');
    return PdfFontResolution.localFontFile(
      fontFilePath: isBold
          ? faces.boldPath ?? faces.regularPath
          : faces.regularPath,
      targetFace: query.face,
      resolvedFace: faces.family,
    );
  }
}

/// מוצא אחרון, גם באנדרואיד שאין בו גופני Windows: כל גופן אמיתי עם עברית
/// מחזיר את האותיות, ו-Tinos מכסה גם לטינית.
class _BundledFontResolver implements PdfFontResolver {
  const _BundledFontResolver();

  @override
  PdfFontResolution resolve(
    PdfFontQuery query,
    PdfFontResolveContext context,
  ) {
    return PdfFontResolution(
      loadData: ({onProgress}) async {
        final data = await rootBundle.load(
          PdfFontFallback.bundledFallbackAsset,
        );
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
      targetFace: query.face,
      resolvedFace: 'Tinos',
    );
  }
}
