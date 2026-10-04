import 'package:path/path.dart' as p;

import 'semantic_model_identity.dart';

/// שם תיקיית חבילת המודל, ליד `seforim.db`.
const String kSemanticModelFolderName = 'meivin-round2-onnx';

/// שם קובץ ה-tokenizer בחבילת המודל.
const String kSemanticTokenizerFileName = 'tokenizer.json';

/// שם קובץ הזהות בחבילת המודל.
const String kSemanticModelIdentityFileName = 'model.json';

/// נתיבי החיפוש הסמנטי במכשיר.
///
/// `<root>` הוא ההורה של תיקיית הספרייה — אותו הורה שבו יושב האינדקס הרגיל
/// (`<root>/index`) בברירת המחדל, וממנו ההעברה מעבירה את `vectors`:
/// - חבילת המודל: `<root>/<תיקיית ה-DB>/meivin-round2-onnx/`
/// - סט הוקטורים: `<root>/vectors/`
/// - הורדות זמניות של הוקטורים: `<root>/vectors-download/`
class SemanticPaths {
  /// התיקייה שבה יושב `seforim.db`.
  final String databaseDirectory;

  final String? _root;

  /// [root] — ההורה של תיקיית הספרייה; ברירת המחדל: ההורה של [databaseDirectory].
  const SemanticPaths(this.databaseDirectory, {this._root});

  /// `<root>`.
  String get root => _root ?? p.dirname(databaseDirectory);

  /// תיקיית חבילת המודל.
  String get modelDirectory =>
      p.join(databaseDirectory, kSemanticModelFolderName);

  /// סט הוקטורים, כפי שהוא נמסר למנוע.
  String get vectorsDirectory => p.join(root, 'vectors');

  /// תיקיית ההורדות של סט הוקטורים; נמחקת אחרי התקנה מוצלחת.
  String get vectorsDownloadDirectory => p.join(root, 'vectors-download');

  /// גרף ה-onnx של [quantization].
  String modelFile(SemanticQuantization quantization) =>
      p.join(modelDirectory, quantization.modelFileName);

  /// `tokenizer.json` שליד הגרף.
  String get tokenizerFile =>
      p.join(modelDirectory, kSemanticTokenizerFileName);

  /// `model.json` שליד הגרף.
  String get identityFile =>
      p.join(modelDirectory, kSemanticModelIdentityFileName);

  /// רישיון המודל, כפי שהורד עם החבילה.
  String get licenseFile => p.join(modelDirectory, 'LICENSE');
}
