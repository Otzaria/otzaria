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
  /// גופנים חדשים מסמכים שנפתחו במקביל נפתחים מחדש פעם אחת.
  static Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool useProgressiveLoading = false,
  }) => _openDocument(
    (provider) => PdfDocument.openFile(
      filePath,
      passwordProvider: provider,
      useProgressiveLoading: useProgressiveLoading,
    ),
    passwordProvider: passwordProvider,
  );

  /// גם מסמך שנוצר בזיכרון יכול לקבל אירוע גופנים של פתיחת קובץ חופפת.
  /// מסמך עם גופנים מוטמעים משתתף בגילוי בלי להזדקק לפתיחה נוספת.
  static Future<PdfDocument> openDocument(
    Future<PdfDocument> Function() loader, {
    bool reopenOnFontChange = true,
  }) => _openDocument(
    (_) => loader(),
    reopenOnFontChange: reopenOnFontChange,
  );

  static Future<PdfDocument> _openDocument(
    Future<PdfDocument> Function(PdfPasswordProvider?) loader, {
    PdfPasswordProvider? passwordProvider,
    bool reopenOnFontChange = true,
  }) async {
    Future<PdfDocument> open({required bool allowReopen}) async {
      var opening = _fontLoads.beginOpening();
      Future<String?> requestPassword() async {
        // הזנת סיסמה אינה עבודת מנוע: פתיחות אחרות צריכות להמשיך בינתיים.
        _fontLoads.cancelOpening(opening);
        final password = await passwordProvider!();
        if (password != null) opening = _fontLoads.beginOpening();
        return password;
      }

      try {
        final document = await loader(
          passwordProvider == null ? null : requestPassword,
        );
        final missing = await _reportedMissingFonts(document);
        final fontsChanged = await _fontLoads.completeOpening(opening, missing);
        if (!fontsChanged || !allowReopen) return document;

        // ה־worker חייב להשתחרר מהמסמך לפני פתיחתו מחדש. גם הפתיחה
        // החוזרת משתתפת בגילוי, כי היא עלולה לקבל אירוע של מסמך אחר.
        await document.dispose();
        return open(allowReopen: false);
      } finally {
        _fontLoads.cancelOpening(opening);
      }
    }

    return open(allowReopen: reopenOnFontChange);
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
