import 'package:path/path.dart' as p;

import 'semantic_model_identity.dart';

/// שם תיקיית חבילת המודל, ליד `seforim.db`.
const String kSemanticModelFolderName = 'meivin-qa491-onnx';

/// תיקיות מודל של גרסאות קודמות; נמחקות אחרי שהמודל הנוכחי הותקן.
const List<String> kLegacySemanticModelFolderNames = [
  'meivin-round2-onnx',
  'pardes107-onnx',
  'pardes107-windows-onnx',
];

/// שם קובץ ה-tokenizer בחבילת המודל.
const String kSemanticTokenizerFileName = 'tokenizer.json';

/// שם קובץ הזהות בחבילת המודל.
const String kSemanticModelIdentityFileName = 'model.json';

/// נתיבי החיפוש הסמנטי במכשיר.
///
/// `<root>` הוא ההורה של תיקיית הספרייה — אותו הורה שבו יושב האינדקס הרגיל
/// (`<root>/index`) בברירת המחדל, וממנו ההעברה מעבירה את `vectors`:
/// - חבילת המודל: `<root>/<תיקיית ה-DB>/meivin-qa491-onnx/`, או
///   `pardesqa491-onnx/` כשנבחר פרדס.
/// - סט הוקטורים: `<root>/vectors/`
/// - הורדות זמניות של הוקטורים: `<root>/vectors-download/`
class SemanticPaths {
  /// התיקייה שבה יושב `seforim.db`.
  final String databaseDirectory;

  final String? _root;

  final SemanticModelChoice modelChoice;

  /// [root] — ההורה של תיקיית הספרייה; ברירת המחדל: ההורה של [databaseDirectory].
  const SemanticPaths(
    this.databaseDirectory, {
    this._root,
    this.modelChoice = SemanticModelChoice.meivin,
  });

  SemanticPaths forModel(SemanticModelChoice choice) => SemanticPaths(
    databaseDirectory,
    root: _root,
    modelChoice: choice,
  );

  /// `<root>`.
  String get root => _root ?? p.dirname(databaseDirectory);

  /// תיקיית חבילת המודל.
  String get modelDirectory => p.join(
    databaseDirectory,
    modelChoice == SemanticModelChoice.pardesQa491
        ? 'pardesqa491-onnx'
        : kSemanticModelFolderName,
  );

  /// תיקיות המודל של גרסאות קודמות.
  Iterable<String> get legacyModelDirectories => kLegacySemanticModelFolderNames
      .map((name) => p.join(databaseDirectory, name));

  /// סט הוקטורים, כפי שהוא נמסר למנוע.
  String get vectorsDirectory => p.join(root, 'vectors');

  /// תיקיית ההורדות של סט הוקטורים; נמחקת אחרי התקנה מוצלחת.
  String get vectorsDownloadDirectory => p.join(root, 'vectors-download');

  /// גרף ה-onnx של [quantization].
  String modelFile(SemanticQuantization quantization) => p.join(
    modelDirectory,
    modelChoice == SemanticModelChoice.pardesQa491 &&
            quantization == SemanticQuantization.int8
        ? 'model.onnx'
        : quantization.modelFileName,
  );

  /// `tokenizer.json` שליד הגרף.
  String get tokenizerFile =>
      p.join(modelDirectory, kSemanticTokenizerFileName);

  /// `model.json` שליד הגרף.
  String get identityFile =>
      p.join(modelDirectory, kSemanticModelIdentityFileName);

  /// רישיון המודל, כפי שהורד עם החבילה.
  String get licenseFile => p.join(
    modelDirectory,
    modelChoice == SemanticModelChoice.pardesQa491
        ? 'LICENSE-AGPL-3.0.txt'
        : 'LICENSE',
  );
}
