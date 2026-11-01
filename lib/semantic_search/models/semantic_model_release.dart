import 'package:equatable/equatable.dart';

import 'semantic_model_identity.dart';
import 'semantic_paths.dart';

/// שם קובץ הרישיון בחבילת המודל.
const String kSemanticModelLicenseFileName = 'LICENSE';

/// קובץ אחד ב-release של המודל, עם ה-SHA-256 שלו נעוץ בקוד.
class SemanticModelFile extends Equatable {
  final String name;
  final int size;
  final String sha256;

  /// אותו קובץ לבדו בתוך zip, להורדה כשהקובץ עצמו לא ירד; התוכן מאומת באותו SHA-256.
  final SemanticModelFile? zipped;

  const SemanticModelFile({
    required this.name,
    required this.size,
    required this.sha256,
    this.zipped,
  });

  @override
  List<Object?> get props => [name, size, sha256, zipped];
}

/// release של חבילת מודל ב-GitHub: `<baseUrl>/<שם הקובץ>`.
///
/// ה-checksum של החבילה ב-`model.json` הוא digest של המנוע מעל כמה קבצים, ולא
/// SHA-256 של קובץ; לכן כל קובץ מאומת כאן לפי ה-SHA-256 הנעוץ שלו.
class SemanticModelRelease extends Equatable {
  final String baseUrl;
  final SemanticModelFile graph;
  final SemanticModelFile tokenizer;

  /// גרף מסמכים נפרד, שמורד רק כשמבקשים הדגשת פסקאות.
  final SemanticModelFile? passageGraph;

  /// עותק ה-`model.json` שב-release; חייב להיות זהה לנכס המצורף.
  final SemanticModelFile identity;
  final SemanticModelFile license;

  const SemanticModelRelease({
    required this.baseUrl,
    required this.graph,
    required this.tokenizer,
    required this.identity,
    required this.license,
    this.passageGraph,
  });

  String urlOf(SemanticModelFile file) => '$baseUrl/${file.name}';

  /// סך הבתים בהתקנה הראשונית; גרף הפסקאות מורד בנפרד.
  int get downloadSize =>
      graph.size + tokenizer.size + identity.size + license.size;

  @override
  List<Object?> get props => [
    baseUrl,
    graph,
    tokenizer,
    identity,
    license,
    passageGraph,
  ];
}

/// מקור ההורדה של כל דיוק; `null` — אין release, והאפשרות אינה מוצגת.
const Map<SemanticQuantization, SemanticModelRelease?>
kSemanticModelReleases = {
  SemanticQuantization.int8: SemanticModelRelease(
    baseUrl:
        'https://github.com/Otzaria/otzaria-semantic-search/releases/download/model-meivin-qa491-int8-v1',
    graph: SemanticModelFile(
      name: 'query.int8.onnx',
      size: 42625431,
      sha256:
          '82b87180616cee55357b90858f327f4d98b86b2e5589f6771d50b788ad383597',
    ),
    passageGraph: SemanticModelFile(
      name: 'document.fp32.onnx',
      size: 168145648,
      sha256:
          '46ba402ce20693d0a3b65aa557a368a3535bbb2a5a1f559d848e803788f7b667',
    ),
    tokenizer: SemanticModelFile(
      name: kSemanticTokenizerFileName,
      size: 2191362,
      sha256:
          '0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9',
      zipped: SemanticModelFile(
        name: '$kSemanticTokenizerFileName.zip',
        size: 445252,
        sha256:
            '07353eea8a9e5036f5a50691424b7818fa7768a3f5220a8daf8505f4b8bd3da0',
      ),
    ),
    identity: SemanticModelFile(
      name: kSemanticModelIdentityFileName,
      size: 634,
      sha256:
          '58227b5df294a2c20a706482de5d431875941f22ee5007cf20ddc84536801fad',
    ),
    license: SemanticModelFile(
      name: kSemanticModelLicenseFileName,
      size: 3992,
      sha256:
          '92267258dabd9077849cc5ab63a5b0b0b3ca9849e1112fd0d13d9691df7e0739',
    ),
  ),
  SemanticQuantization.fp32: null,
};
