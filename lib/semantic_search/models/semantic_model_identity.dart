import 'dart:convert';

import 'package:equatable/equatable.dart';

/// דיוק המשקלות של מודל השאילתות. אותו סט וקטורים משרת את שניהם.
enum SemanticQuantization {
  /// ברירת המחדל של דיוק המשקולות.
  int8,

  /// דיוק נוסף, רק כאשר פורסמה חבילה תואמת.
  fp32;

  /// שם הגרף בחבילת המודל, למשל `query.int8.onnx`.
  String get modelFileName => switch (this) {
    int8 => 'query.int8.onnx',
    fp32 => 'document.fp32.onnx',
  };

  /// ממפה ערך שמור בהגדרות; ערך לא מוכר חוזר לברירת המחדל.
  static SemanticQuantization parse(String? value) =>
      values.asNameMap()[value] ?? SemanticQuantization.int8;
}

/// חבילת שאילתות אחת שהזהות מתירה: ה-checksum (SHA-256) של גרף ה-onnx.
class SemanticQueryPackage extends Equatable {
  final String checksum;
  final String quantization;

  const SemanticQueryPackage({
    required this.checksum,
    required this.quantization,
  });

  @override
  List<Object?> get props => [checksum, quantization];
}

/// זהות המודל (`model.json`) שאיתה נבנו הוקטורים.
///
/// [rawJson] נמסר למנוע כמות שהוא, בפתיחה ובהתקנה; שאר השדות מפוענחים
/// לאימות ההורדה ולטלמטריה.
class SemanticModelIdentity extends Equatable {
  /// מזהה משפחת המודל (`family_id`).
  final String familyId;

  /// רוחב כל וקטור (`embedding_dim`).
  final int embeddingDim;

  /// SHA-256 של `tokenizer.json` (`tokenizer_checksum`).
  final String tokenizerChecksum;

  /// תצורת החלוקה לקטעים שאיתה נבנו הוקטורים (`chunking_identity`).
  final int chunkingIdentity;

  /// החבילות שמותר לשאול איתן (`query_packages`).
  final List<SemanticQueryPackage> queryPackages;

  /// טקסט הקובץ המקורי.
  final String rawJson;

  const SemanticModelIdentity({
    required this.familyId,
    required this.embeddingDim,
    required this.tokenizerChecksum,
    required this.chunkingIdentity,
    required this.queryPackages,
    required this.rawJson,
  });

  /// מפענח את טקסט `model.json`.
  ///
  /// זורק [FormatException] כששדה חובה חסר או מסוג שגוי.
  factory SemanticModelIdentity.parse(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('model.json אינו אובייקט JSON');
    }
    final packages = decoded['query_packages'];
    if (packages is! List || packages.isEmpty) {
      throw const FormatException('model.json: query_packages חסר');
    }
    return SemanticModelIdentity(
      familyId: _string(decoded, 'family_id'),
      embeddingDim: _int(decoded, 'embedding_dim'),
      tokenizerChecksum: _string(decoded, 'tokenizer_checksum'),
      chunkingIdentity: readSemanticChunkingIdentity(
        decoded['chunking_identity'],
        rawJson,
      ),
      queryPackages: [
        for (final package in packages)
          if (package is Map<String, dynamic>)
            SemanticQueryPackage(
              checksum: _string(package, 'checksum'),
              quantization: _string(package, 'quantization'),
            ),
      ],
      rawJson: rawJson,
    );
  }

  /// החבילה של [quantization], או `null` כשהזהות אינה מתירה אותה.
  SemanticQueryPackage? packageFor(SemanticQuantization quantization) {
    for (final package in queryPackages) {
      if (package.quantization == quantization.name) return package;
    }
    return null;
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('model.json: $key חסר');
  }

  static int _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw FormatException('model.json: $key חסר');
  }

  @override
  List<Object?> get props => [
    familyId,
    embeddingDim,
    tokenizerChecksum,
    chunkingIdentity,
    queryPackages,
    rawJson,
  ];
}

/// Dart VM מחזיק int חתום, אבל זהות החלוקה היא UInt64. ערך גדול מוחזק כאן
/// כדפוס הסיביות החתום שלו, להשוואה בלבד; ה-JSON המקורי נשלח למנוע ללא שינוי.
/// לא ממירים מ-double: שני UInt64 סמוכים עלולים לקבל בדיוק אותו double.
int readSemanticChunkingIdentity(Object? decoded, String rawJson) {
  if (decoded is int && decoded >= 0) return decoded;
  if (decoded is double && decoded.isFinite) {
    final matches = RegExp(
      r'"chunking_identity"\s*:\s*(0|[1-9][0-9]*)(?=\s*[,}])',
    ).allMatches(rawJson).toList();
    if (matches.length == 1) {
      final exact = BigInt.parse(matches.single.group(1)!);
      if (exact.bitLength == 64 && decoded == exact.toDouble()) {
        return exact.toSigned(64).toInt();
      }
    }
  }
  throw const FormatException('chunking_identity אינו UInt64 תקין');
}

/// בחירת מודל: Meivin נשאר ברירת המחדל; פרדס דורש סט וקטורים נפרד.
enum SemanticModelChoice {
  meivin,
  pardesQa491;

  static SemanticModelChoice parse(String? value) =>
      values.asNameMap()[value] ?? meivin;
}

const String kCompactPardesModelFamilyId = 'otzaria/Pardes-QA491-int8-384';
