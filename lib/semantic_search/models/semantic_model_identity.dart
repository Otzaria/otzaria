import 'dart:convert';

import 'package:equatable/equatable.dart';

/// דיוק המשקלות של מודל השאילתות. אותו סט וקטורים משרת את שניהם.
enum SemanticQuantization {
  /// ברירת המחדל: קובץ של כ-42MB.
  int8,

  /// אופציונלי: קובץ של כ-168MB, ותוצאות כמעט זהות.
  fp32;

  /// שם הגרף בחבילת המודל, למשל `seforim-embed-round2-int8.onnx`.
  String get modelFileName => 'seforim-embed-round2-$name.onnx';

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

  /// החבילות שמותר לשאול איתן (`query_packages`).
  final List<SemanticQueryPackage> queryPackages;

  /// טקסט הקובץ המקורי.
  final String rawJson;

  const SemanticModelIdentity({
    required this.familyId,
    required this.embeddingDim,
    required this.tokenizerChecksum,
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
    queryPackages,
    rawJson,
  ];
}
