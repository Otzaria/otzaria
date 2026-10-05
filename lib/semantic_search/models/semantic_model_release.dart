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

  /// עותק ה-`model.json` שב-release; חייב להיות זהה לנכס המצורף.
  final SemanticModelFile identity;
  final SemanticModelFile license;

  const SemanticModelRelease({
    required this.baseUrl,
    required this.graph,
    required this.tokenizer,
    required this.identity,
    required this.license,
  });

  String urlOf(SemanticModelFile file) => '$baseUrl/${file.name}';

  /// סך הבתים להורדה.
  int get downloadSize =>
      graph.size + tokenizer.size + identity.size + license.size;

  @override
  List<Object?> get props => [baseUrl, graph, tokenizer, identity, license];
}

/// מקור ההורדה של כל דיוק; `null` — אין release, והאפשרות אינה מוצגת.
const Map<SemanticQuantization, SemanticModelRelease?>
kSemanticModelReleases = {
  SemanticQuantization.int8: SemanticModelRelease(
    baseUrl:
        'https://github.com/Otzaria/otzaria-semantic-search/releases/download/model-meivin-round2-int8-v1',
    graph: SemanticModelFile(
      name: 'seforim-embed-round2-int8.onnx',
      size: 42489219,
      sha256:
          '659226865abd3a1bc833565ae6b2e2f48abdd7136285824a12966d4d3294cbf8',
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
      size: 656,
      sha256:
          'a27b103ea5dc50be674e6e6696d8f8ea09639ac3808cd1a48dcf2d70a0b47d1c',
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
