/// המבנה שמסייע ההורדה מכין לחיפוש הסמנטי, ושהאפליקציה מזהה ב-`<root>`
/// (ההורה של תיקיית הספרייה, ראה `SemanticPaths.root`):
///
/// ```text
/// <root>/semantic-import/pardesqa491-onnx/      קובצי המודל
/// <root>/semantic-import/vectors/              קובצי הוקטורים והמניפסט שלהם
/// ```
///
/// קובץ פשוט, בלי Flutter — גם `tool/release` קורא אותו.
library;

/// תיקיית הנתונים המוכנים, ליד תיקיית הספרייה.
const String kSemanticImportFolderName = 'semantic-import';

/// תת-התיקייה של סט הוקטורים בתוך [kSemanticImportFolderName].
const String kSemanticImportVectorsFolderName = 'vectors';

/// המאגר שבו מתפרסמים releases הוקטורים.
const String kSemanticVectorsRepository = 'Otzaria/SeforimLibrary';

/// קידומת ושם הסיום של מניפסט הוקטורים ב-release.
const String kSemanticVectorsManifestPrefix = 'otzaria-vectors-';
const String kSemanticVectorsManifestSuffix = '.manifest.json';

/// כתובת ההורדה של נכס ב-release הוקטורים של [libraryTag]; [releaseTagPrefix]
/// היא תחילית המשפחה.
String semanticVectorsAssetUrl(
  String libraryTag,
  String name, {
  String releaseTagPrefix = 'vectors-pardesqa491-windows-',
}) =>
    'https://github.com/$kSemanticVectorsRepository/releases/download/'
    '$releaseTagPrefix$libraryTag/$name';
