/// קבועים ועזרים לסיווג סוגי קישורים ב־seforim.db.
class LinkTypes {
  LinkTypes._();

  static const String commentary = 'COMMENTARY';
  static const String superCommentary = 'SUPER_COMMENTARY';
  static const String targum = 'TARGUM';
  static const String reference = 'REFERENCE';
  static const String source = 'SOURCE';
  static const String midrash = 'MIDRASH';
  static const String quotation = 'QUOTATION';
  static const String mesoratHashas = 'MESORAT_HASHAS';
  static const String einMishpat = 'EIN_MISHPAT';
  static const String diburHamatchil = 'DIBUR_HAMATCHIL';
  static const String parshanut = 'PARSHANUT';
  static const String mishnahInTalmud = 'MISHNAH_IN_TALMUD';
  static const String related = 'RELATED';
  static const String other = 'OTHER';
  static const String quotationAuto = 'QUOTATION_AUTO';
  static const String quotationAutoTanakh = 'QUOTATION_AUTO_TANAKH';
  static const String relatedPassage = 'RELATED_PASSAGE';
  static const String allusion = 'ALLUSION';
  static const String law = 'LAW';
  static const String footnotes = 'FOOTNOTES';
  static const String liturgy = 'LITURGY';
  static const String linker = 'LINKER';
  static const String summary = 'SUMMARY';
  static const String sifreiMitzvot = 'SIFREI_MITZVOT';
  static const String essay = 'ESSAY';
  static const String none = 'NONE';

  /// תוויות עבריות המותרות בקובצי קישורים של המשתמש.
  static const Map<String, String> hebrewConnectionTypes = {
    'פירוש': commentary,
    'תרגום': targum,
    'הפניה': reference,
    'מקור': source,
    'אחר': other,
  };

  /// כינויי סוגים בקובצי native; סוגים שאינם במפה נשמרים כמות שהם.
  static const Map<String, String> nativeConnectionTypeAliases = {
    'NONE': other,
    'SUPERCOMMENTARY': superCommentary,
    'QUOTATION_AUTO': quotation,
    'QUOTATION_AUTO_TANAKH': quotation,
    'RELATED_PASSAGE': related,
    'EIN_MISHPAT_/_NER_MITSVAH': einMishpat,
    'EIN_MISHPAT_/_NER_MITZVAH': einMishpat,
    'SIFREI_MITSVOT': sifreiMitzvot,
    'ELLUCIDATION': elucidation,
    'FOOTNOTE': footnotes,
  };

  /// ביאורים תלויי־טקסט, ולכן מוצגים כמפרשים ולא כהפניות.
  static const String elucidation = 'ELUCIDATION';
  static const String explication = 'EXPLICATION';

  /// סוגי קישור תלויי-טקסט — טקסטים שתלויים בטקסט הבסיס (פירוש/תרגום/מדרש
  /// וכד׳) ומוצגים בפאנל המפרשים. "עין משפט" הוא כלי הפניה ולכן מוצג בקישורים.
  static const Set<String> dependentTextTypes = {
    commentary,
    superCommentary,
    targum,
    midrash,
    parshanut,
    diburHamatchil,
    elucidation,
    explication,
    footnotes,
  };

  /// סוגי הפניה צדדית — קישורים שאינם טקסט תלוי, ולכן שני צדדיהם שקולים:
  /// אזכור בין שני חיבורים עומד באותה מידה משני הכיוונים. עד סכמה 3 הם עלו
  /// רק מצד ה-source השמור, ולכן דיכוי הצד הזה היה מעלים אותם לגמרי במקום
  /// להעביר אותם לצד המצטט; מכאן הצורך בדו-כיווניות.
  ///
  /// מכסה בדיוק את ערכי ה-ConnectionType שהגנרטור יכול לכתוב: תלויי-טקסט
  /// ב-[dependentTextTypes], הפניות כאן, ו-[source] (וירטואלי, לא נשמר)
  /// ו-[linker] חד-כיווניים. ערכים שאינם ConnectionType ([altToc]) וכאלה
  /// ש-fromKnownStringOrNull ממפה לסוג אחר לפני האחסון
  /// ([quotationAuto], [relatedPassage], [none]) אינם כאן — הם לא יכולים
  /// להופיע בעמודה ולכן היו רק פרמטרים מתים בשאילתה. [footnotes] עבר
  /// ל-[dependentTextTypes] משנעשה ConnectionType אמיתי.
  ///
  /// [linker] מוחרג משום שהוא תוצר הלינקר שלנו ולא של ספריא: הוא לעולם אינו
  /// עובר דרך ה-mask המיוצא, ולכן לא ניתן לדעת אם צדו הוסתר. הנימוק אינו
  /// נפח — ל-[other], שכן נכלל, יש יותר קישורים ממנו.
  static const Set<String> referenceTypes = {
    reference,
    quotation,
    mesoratHashas,
    einMishpat,
    mishnahInTalmud,
    related,
    other,
    sifreiMitzvot,
    essay,
    allusion,
    liturgy,
    law,
    summary,
  };

  /// סוגים שהשאילתה ההפוכה מחזירה כשה-DB תומך בדיכוי פר-צד. בלי התמיכה
  /// חוזרים בדיוק להתנהגות הקודמת — רק תלויי-טקסט.
  static List<String> inverseQueryTypes({required bool bidirectional}) => [
    ...dependentTextTypes,
    if (bidirectional) ...referenceTypes,
  ];

  /// האם הקישור הוא תלוי-טקסט (מפרש) — מוצג בפאנל המפרשים ולא כהפניה צדדית.
  ///
  /// ההשוואה אינה תלוית רישיות — חלק ממקורות הנתונים עשויים לספק ערכים
  /// באותיות קטנות (כפי שקורה גם בטסטים).
  static bool isDependentTextLink(String? connectionType) {
    if (connectionType == null) return false;
    return dependentTextTypes.contains(normalize(connectionType));
  }

  /// סוגי המפרשים שמקבלים צ׳יפ סינון בפאנל המפרשים, בסדר התצוגה. הערכים
  /// קנוניים, ולכן [explication] מיוצג כאן ע"י [elucidation].
  ///
  /// [commentary] ו-[superCommentary] מוחרגים בכוונה: הם רוב מוחלט של הקישורים
  /// (2.2M מול עשרות אלפים), וצ׳יפ שכולל כמעט הכל אינו מסנן כלום.
  static const List<String> commentaryFilterTypes = [
    targum,
    midrash,
    parshanut,
    diburHamatchil,
    elucidation,
  ];

  /// האם סוג המפרש מקבל צ׳יפ סינון משלו בפאנל המפרשים.
  static bool isCommentaryFilterType(String? connectionType) =>
      commentaryFilterTypes.contains(canonicalType(connectionType));

  /// ערך חריג שמגיע מבניית קישורי תוכן העניינים החלופי, ואינו חלק מ-[LinkTypes].
  static const String altToc = 'ALT_TOC';

  /// תוויות עבריות להצגה, לפי הניסוח של ספריא.
  static const Map<String, String> hebrewLabels = {
    commentary: 'פירוש',
    superCommentary: 'פירוש על פירוש',
    targum: 'תרגום',
    midrash: 'מדרש',
    parshanut: 'פרשנות',
    diburHamatchil: 'דיבור המתחיל',
    elucidation: 'ביאור',
    explication: 'ביאור',
    reference: 'עיון',
    quotation: 'ציטוט',
    mesoratHashas: 'מסורת הש"ס',
    einMishpat: 'עין משפט',
    mishnahInTalmud: 'משנה בתלמוד',
    related: 'נושא קרוב',
    source: 'מקור',
    other: 'לא מסווג',
    altToc: 'חלוקה חלופית',
    quotationAuto: 'ציטוט אוטומטי',
    quotationAutoTanakh: 'ציטוט אוטומטי מהתנ"ך',
    relatedPassage: 'קטע קשור',
    allusion: 'אזכור',
    law: 'פסיקת הלכה',
    footnotes: 'הערות שוליים',
    liturgy: 'תפילה',
    linker: 'אוטומטי',
    summary: 'סיכום',
    sifreiMitzvot: 'ספרי מצוות',
    // מוצג כ'לא מסווג' בפאנל (ראה [_canonicalTypes]), אבל התווית נדרשת כאן
    // כדי שהסוג יהיה מוכר — הייבוא נגזר מהמפה הזו.
    essay: 'מאמר',
    none: 'לא מסווג',
  };

  /// תחילית למפתחות צ׳יפ של דור, כדי שלא יתנגשו עם מפתחות סוג-קישור.
  /// המפתח המלא נבנה ב-`CommentaryService.eraChipKey`.
  static const String eraKeyPrefix = 'ERA:';

  /// האם המפתח הוא מפתח צ׳יפ של דור ולא סוג קישור.
  static bool isEraKey(String key) => key.startsWith(eraKeyPrefix);

  /// מפתח צ׳יפ "על <הספר הפתוח>". קבוע ובלי שם הספר, כי `normalize` היה הופך
  /// רווחים בשם עברי לקווים תחתונים והמפתח לא היה שורד שמירה בהגדרות.
  static const String onBookKey = 'ON_BOOK';

  /// סוגי קישור שאין בתווית שלהם מידע שימושי ("לא מסווג", "עיון", "אוטומטי").
  /// קישוריהם מקובצים בצ׳יפים לפי דור מחבר ספר היעד במקום לפי הסוג.
  static const Set<String> eraGroupedTypes = {
    other,
    none,
    related,
    relatedPassage,
    reference,
    linker,
  };

  /// האם קישור מסוג זה מקובץ לפי דור במקום לפי סוג.
  static bool isEraGroupedType(String? connectionType) =>
      eraGroupedTypes.contains(canonicalType(connectionType));

  /// מיזוג סוגים דומים לצ׳יפ קנוני אחד, כדי שפאנל הקישורים הצר לא יוצף.
  static const Map<String, String> _canonicalTypes = {
    quotationAuto: quotation,
    quotationAutoTanakh: quotation,
    relatedPassage: related,
    none: other,
    // תווית חסרת מידע לקורא, ולכן ממוזג ל'לא מסווג' במקום צ׳יפ נפרד.
    essay: other,
    // שני הסוגים נקראים 'ביאור' — בלי מיזוג היו נבנים שני צ׳יפים זהים.
    explication: elucidation,
  };

  /// מנרמל ערך connectionType להשוואה: מקורות שונים מספקים רישיות שונה
  /// (DB באותיות גדולות, JSON באותיות קטנות) ומפרידים ברווח במקום בקו תחתון.
  static String normalize(String? connectionType) {
    // נקרא לכל קישור בספר; ערכי ה-DB כבר קנוניים ולכן מדלגים על ההמרות.
    if (connectionType != null && _isCanonical(connectionType)) {
      return connectionType;
    }
    final trimmed = connectionType?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    return trimmed.toUpperCase().replaceAll(_separators, '_');
  }

  static final RegExp _separators = RegExp(r'[\s-]+');

  /// לא ריק, ורק A-Z, 0-9 ו-`_`: [normalize] היה מחזיר אותו ללא שינוי.
  static bool _isCanonical(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      final isUpper = c >= 0x41 && c <= 0x5A;
      final isDigit = c >= 0x30 && c <= 0x39;
      if (!isUpper && !isDigit && c != 0x5F) return false;
    }
    return true;
  }

  /// הסוג הקנוני שלפיו מקבצים וסופרים בפאנל הקישורים. סוג לא-מוכר נשמר כמות
  /// שהוא (אחרי נרמול) כדי שסוג חדש ב-DB יוצג ולא ייעלם.
  static String canonicalType(String? connectionType) {
    final normalized = normalize(connectionType);
    if (normalized.isEmpty) return other;
    return _canonicalTypes[normalized] ?? normalized;
  }

  /// התווית העברית של סוג הקישור. ערך לא מוכר מוחזר כמות שהוא (ללא נרמול),
  /// כדי שסוג חדש ב-DB יוצג ולא ייעלם.
  static String hebrewLabel(String? connectionType) {
    final normalized = normalize(connectionType);
    if (normalized.isEmpty) return hebrewLabels[other]!;
    return hebrewLabels[normalized] ?? connectionType!.trim();
  }

  /// האם הקישור הוא קשר עיון/הפניה (לא מפרש ולא SOURCE הווירטואלי):
  /// reference, quotation, mesorat hashas, ein mishpat, mishnah in talmud,
  /// related, other.
  static bool isReferenceLikeLink(String? connectionType) {
    if (connectionType == null) return false;
    final normalized = normalize(connectionType);
    return normalized != source && !dependentTextTypes.contains(normalized);
  }

  /// `SOURCE` הוא קשר וירטואלי שנבנה בשאילתת inverse ואינו נשמר כשורת link.
  static bool isVirtualSource(String? connectionType) =>
      connectionType != null && normalize(connectionType) == source;
}
