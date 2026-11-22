/// מימוש הייחוס של חוזה הבחירה במסייע ההורדה (docs/download_assistant.md,
/// "חוזה משותף לכל המסייעים").
///
/// שלושת המסייעים (Inno, SwiftUI, GTK) מממשים את אותו חוזה כל אחד בשפתו. הקובץ
/// הזה הוא הגרסה ההפיכה-לבדיקה שלו: `tool/download_assistant/fixtures/` נגזר
/// ממנו, והמסייעים משווים את עצמם לאותם קבצים.
library;

/// גבול הקובץ הבודד: Windows אינו מריץ exe בגודל 4 GiB ומעלה, ו-FAT32 אינו
/// מחזיק קובץ כזה.
const int kMaxSingleOutputFileSize = 4294967296;

/// סדר הפלטפורמות בעמוד הבחירה.
const List<String> kAssistantPlatforms = [
  'windows',
  'macos',
  'linux',
  'android',
];

/// שם הפלטפורמה למשתמש — באותיות לטיניות, כמו בשמות הרכיבים.
const Map<String, String> kPlatformDisplayNames = {
  'windows': 'Windows',
  'macos': 'macOS',
  'linux': 'Linux',
  'android': 'Android',
};

/// ערך הבחירה "ללא מנהל חבילות" — מתאים רק לרכיבים שאין להם packageFormat.
const String kPortablePackageFormat = 'portable';

/// מחשב היעד: פלטפורמה, ארכיטקטורה ('' כשלפלטפורמה אין רכיבים תלויי
/// ארכיטקטורה) ופורמט חבילה ('' מחוץ ל-Linux).
class AssistantTarget {
  const AssistantTarget({
    required this.platform,
    this.architecture = '',
    this.packageFormat = '',
  });

  final String platform;
  final String architecture;
  final String packageFormat;

  Map<String, String> toJson() => {
    'platform': platform,
    'architecture': architecture,
    'packageFormat': packageFormat,
  };
}

/// ההצעה המסומנת מראש: במחשב עם אינטרנט הספרייה יורדת מתוך התוכנה.
const String kDefaultPresetId = 'basic';

/// סדר ההצגה של ההצעות. הוא אינו סדר ההערכה ב-[buildPresets], שקובע איזו
/// כפולה מושמטת.
const List<String> kPresetDisplayOrder = [
  'basic',
  'full-indexed',
  'full',
  'update',
];

/// נתוני החיפוש החכם, שהתוכנה המותקנת קוראת מתיקיית הפלט (`outputFolder`).
/// הם חלק מ"מלאה" ומ"מלאה + אינדקס" — למחשב בלי אינטרנט — ואינם בשאר ההצעות.
const Set<String> kOfflineDataTypes = {'semantic-model', 'semantic-vectors'};

/// הצעה מוכנה: מזהה יציב, הטקסט למשתמש, והרכיבים בסדר המניפסט.
class AssistantPreset {
  const AssistantPreset({
    required this.id,
    required this.caption,
    required this.description,
    required this.members,
  });

  final String id;
  final String caption;
  final String description;
  final List<String> members;

  Map<String, Object> toJson() => {'id': id, 'members': members};
}

List<Map<String, Object?>> _components(Map<String, Object?> manifest) =>
    (manifest['components'] as List).cast<Map<String, Object?>>();

String _field(Map<String, Object?> component, String key) =>
    (component[key] as String?) ?? '';

/// טקסט הרכיב למשתמש ([key] = name / description / outputNote). באנגלית
/// השדה `<key>En`, ובהיעדרו (release ישן) — העברי.
String componentText(
  Map<String, Object?> component,
  String key, {
  required bool english,
}) {
  final translated = english ? _field(component, '${key}En') : '';
  return translated.isNotEmpty ? translated : _field(component, key);
}

bool _isWildcard(String value) => value.isEmpty || value == 'any';

/// רכיב מתאים ליעד כשכל אחד משלושת השדות חסר, `any`, או שווה ליעד.
bool componentFitsTarget(
  Map<String, Object?> component,
  AssistantTarget target,
) {
  final platform = _field(component, 'platform');
  if (!_isWildcard(platform) && platform != target.platform) return false;
  final architecture = _field(component, 'architecture');
  if (!_isWildcard(architecture) && architecture != target.architecture) {
    return false;
  }
  final format = _field(component, 'packageFormat');
  if (!_isWildcard(format) && format != target.packageFormat) return false;
  return true;
}

List<String> _ids(Map<String, Object?> component, String key) =>
    ((component[key] as List?) ?? const []).cast<String>();

/// נכס שאי אפשר להפעיל: exe בגודל 4 GiB ומעלה, ש-Windows מסרב להריץ.
bool _assetIsUnrunnable(Map<String, Object?> asset) =>
    (asset['name'] as String).toLowerCase().endsWith('.exe') &&
    (asset['size'] as int) >= kMaxSingleOutputFileSize;

bool _fitsAndRunnable(Map<String, Object?> component, AssistantTarget target) =>
    componentFitsTarget(component, target) &&
    !((component['assets'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .any(_assetIsUnrunnable);

/// המתקין שיתקין את [component] ביעד — הראשון ב-`installedBy` שמוצע בו.
/// null כשאין לרכיב `installedBy`, או כשאף אחד ממתקיניו אינו מוצע ביעד.
String? installerFor(
  Map<String, Object?> manifest,
  Map<String, Object?> component,
  AssistantTarget target,
) {
  final byId = {for (final c in _components(manifest)) c['id']: c};
  for (final id in _ids(component, 'installedBy')) {
    final installer = byId[id];
    if (installer != null && _fitsAndRunnable(installer, target)) return id;
  }
  return null;
}

/// רכיב שהמסייע מציע ליעד — בהצעות ובבחירה האישית: מתאים ליעד, אין בו exe
/// שאי אפשר להפעיל, ואם יש לו `installedBy` — אחד ממתקיניו מוצע ביעד.
bool componentIsOffered(
  Map<String, Object?> manifest,
  Map<String, Object?> component,
  AssistantTarget target,
) {
  if (!_fitsAndRunnable(component, target)) return false;
  if (_ids(component, 'installedBy').isEmpty) return true;
  return installerFor(manifest, component, target) != null;
}

/// קבוצת הבחירה-אחת-מתוך בבחירה האישית: הדרכים החלופיות להתקין את התוכנה.
const String kApplicationChoiceGroup = 'application';

/// שורה בבחירה האישית. [locked] — מסומנת תמיד ואי אפשר לבטל אותה; [group] —
/// שורות עם אותה קבוצה הן בחירה אחת-מתוך (רדיו), '' — תיבת סימון.
typedef CustomChoice = ({
  String id,
  int downloadSize,
  bool locked,
  String group,
});

Map<String, Object> customChoiceToJson(CustomChoice choice) => {
  'id': choice.id,
  'downloadSize': choice.downloadSize,
  'locked': choice.locked,
  'group': choice.group,
};

/// השורות בבחירה האישית, בסדר המניפסט: הדרך להתקין את התוכנה ורכיבי הרשות.
///
/// גרסה ניידת אינה מוצגת — היא צורה חלופית של אותה תוכנה. כשהמתקין הרגיל
/// פורס ספרייה שלצדו, החבילה המלאה מיותרת ואינה מוצגת, והמתקין נעול. אחרת
/// התוכנה והחבילה המלאה הן בחירה אחת-מתוך, כדי שלא יורדו שתיהן.
List<CustomChoice> customChoices(
  Map<String, Object?> manifest,
  AssistantTarget target,
) {
  final byId = {for (final c in _components(manifest)) c['id']: c};
  final offered = [
    for (final component in _components(manifest))
      if (componentIsOffered(manifest, component, target) &&
          _field(component, 'type') != 'application-portable')
        component,
  ];
  final installerTakesLibrary = offered.any((component) {
    final installer = installerFor(manifest, component, target);
    return installer != null &&
        _field(byId[installer]!, 'type') == 'application';
  });
  final rows = [
    for (final component in offered)
      if (_field(component, 'partOf').isEmpty &&
          !(installerTakesLibrary &&
              _field(component, 'type') == 'application-bundle'))
        component,
  ];
  bool isInstaller(Map<String, Object?> c) =>
      const {'application', 'application-bundle'}.contains(_field(c, 'type'));
  final radio = rows.where(isInstaller).length > 1;
  return [
    for (final component in rows)
      (
        id: component['id'] as String,
        downloadSize: offered
            .where(
              (c) => c == component || _field(c, 'partOf') == component['id'],
            )
            .fold(0, (sum, c) => sum + (c['downloadSize'] as int)),
        locked: isInstaller(component) && !radio,
        group: isInstaller(component) && radio ? kApplicationChoiceGroup : '',
      ),
  ];
}

/// הפלטפורמות שיש להן לפחות רכיב ייעודי אחד (רכיב `any` לבדו אינו מספיק).
List<String> platformChoices(Map<String, Object?> manifest) {
  final present = _components(
    manifest,
  ).map((c) => _field(c, 'platform')).toSet();
  return [
    for (final platform in kAssistantPlatforms)
      if (present.contains(platform)) platform,
  ];
}

/// הארכיטקטורות של רכיבי הפלטפורמה. עמוד הארכיטקטורה מוצג רק כשיש יותר
/// מאחת; x64 תמיד ראשונה.
List<String> architectureChoices(
  Map<String, Object?> manifest,
  String platform,
) {
  final found = <String>{};
  for (final component in _components(manifest)) {
    if (_field(component, 'platform') != platform) continue;
    final architecture = _field(component, 'architecture');
    if (!_isWildcard(architecture)) found.add(architecture);
  }
  final sorted = found.toList()..sort();
  if (sorted.remove('x64')) sorted.insert(0, 'x64');
  return sorted;
}

/// פורמטי החבילה שאפשר לבחור ליעד. `portable` מוצע כשיש רכיב תוכנה שאינו
/// תלוי מנהל חבילות (ארכיון נייד או חבילה מלאה).
List<String> packageFormatChoices(
  Map<String, Object?> manifest,
  String platform,
  String architecture,
) {
  final formats = <String>{};
  var portable = false;
  for (final component in _components(manifest)) {
    if (_field(component, 'platform') != platform) continue;
    final componentArch = _field(component, 'architecture');
    if (!_isWildcard(componentArch) && componentArch != architecture) continue;
    final format = _field(component, 'packageFormat');
    if (!_isWildcard(format)) {
      formats.add(format);
    } else if (_field(component, 'type').startsWith('application')) {
      portable = true;
    }
  }
  if (formats.isEmpty) return const [];
  final sorted = formats.toList()..sort();
  return [...sorted, if (portable) kPortablePackageFormat];
}

const Set<String> _debFamily = {
  'debian',
  'ubuntu',
  'linuxmint',
  'pop',
  'elementary',
  'zorin',
  'raspbian',
  'kali',
  'neon',
  'deepin',
  'mx',
};

const Set<String> _rpmFamily = {
  'fedora',
  'rhel',
  'centos',
  'rocky',
  'almalinux',
  'ol',
  'suse',
  'opensuse',
  'sles',
  'mageia',
  'openmandriva',
  'nobara',
};

/// פורמט ברירת המחדל מתוך תוכן `/etc/os-release` (null = לא ב-Linux או
/// שהקובץ לא נקרא). ID נבדק לפני ID_LIKE; משפחה לא מוכרת → portable.
String defaultPackageFormat(String? osRelease, List<String> choices) {
  String pick(String preferred) => choices.contains(preferred)
      ? preferred
      : (choices.isEmpty ? '' : choices.first);
  if (osRelease == null) return pick('deb');

  final values = <String, String>{};
  for (final line in osRelease.split('\n')) {
    final index = line.indexOf('=');
    if (index <= 0) continue;
    var value = line.substring(index + 1).trim();
    if (value.length >= 2 &&
        (value.startsWith('"') || value.startsWith("'")) &&
        value.endsWith(value[0])) {
      value = value.substring(1, value.length - 1);
    }
    values[line.substring(0, index).trim()] = value.toLowerCase();
  }
  final tokens = [
    values['ID'] ?? '',
    ...(values['ID_LIKE'] ?? '').split(RegExp(r'\s+')),
  ].where((t) => t.isNotEmpty);
  for (final token in tokens) {
    final family = token.startsWith('opensuse') ? 'opensuse' : token;
    if (_debFamily.contains(family)) return pick('deb');
    if (_rpmFamily.contains(family)) return pick('rpm');
  }
  return pick(kPortablePackageFormat);
}

List<String> _collect(
  Map<String, Object?> manifest,
  AssistantTarget target, {
  Set<String>? types,
  bool requiredOnly = false,
}) => [
  for (final component in _components(manifest))
    if (componentIsOffered(manifest, component, target) &&
        (!requiredOnly || component['required'] == true) &&
        (types == null || types.contains(_field(component, 'type'))))
      component['id'] as String,
];

/// סגירת הבחירה: כל `dependsOn` שמוצע ביעד (שאינו מוצע — מדולג), ולכל רכיב
/// עם `installedBy` שאף מתקין שלו אינו בבחירה — המתקין מ-[installerFor].
List<String> withDependencies(
  Map<String, Object?> manifest,
  Iterable<String> members,
  AssistantTarget target,
) {
  final components = _components(manifest);
  final byId = {for (final c in components) c['id'] as String: c};
  final closed = members.toSet();
  var changed = true;
  while (changed) {
    changed = false;
    for (final id in closed.toList()) {
      final component = byId[id];
      if (component == null) continue;
      for (final dependency in _ids(component, 'dependsOn')) {
        final required = byId[dependency];
        if (required == null ||
            !componentIsOffered(manifest, required, target)) {
          continue;
        }
        if (closed.add(dependency)) changed = true;
      }
      final installers = _ids(component, 'installedBy');
      if (installers.isEmpty || installers.any(closed.contains)) continue;
      final installer = installerFor(manifest, component, target);
      if (installer != null && closed.add(installer)) changed = true;
    }
  }
  return [
    for (final component in components)
      if (closed.contains(component['id'])) component['id'] as String,
  ];
}

/// ההצעות ב-[kPresetDisplayOrder]. הצעה ריקה מושמטת, וכך גם הצעה זהה להצעה
/// שהוערכה לפניה — בסדר מלאה + אינדקס, מלאה, בסיסית, עדכון, כדי שהשם המפורט
/// יותר יישאר. "בחירה אישית" אינה כאן — היא תמיד האחרונה ואינה נגזרת.
List<AssistantPreset> buildPresets(
  Map<String, Object?> manifest,
  AssistantTarget target,
) {
  final components = _components(manifest);
  final offline = _collect(manifest, target, types: kOfflineDataTypes);

  // חבילה יחד עם כל רכיב מוצע שהיא ב-`installedBy` שלו.
  List<String> withInstalled(Map<String, Object?> bundle) => [
    bundle['id'] as String,
    for (final component in components)
      if (_ids(component, 'installedBy').contains(bundle['id']) &&
          componentIsOffered(manifest, component, target))
        component['id'] as String,
  ];
  int sizeOf(List<String> ids) => components
      .where((c) => ids.contains(c['id']))
      .fold(0, (sum, c) => sum + (c['downloadSize'] as int));

  Map<String, Object?>? bundle;
  Map<String, Object?>? indexed;
  for (final component in components) {
    if (!componentIsOffered(manifest, component, target)) continue;
    if (_field(component, 'type') != 'application-bundle') continue;
    if (bundle == null ||
        (component['downloadSize'] as int) > (bundle['downloadSize'] as int)) {
      bundle = component;
    }
    // החבילה המאונדקסת: ספרייה מוצעת מותקנת על ידה.
    final installsLibrary = components.any(
      (c) =>
          _field(c, 'type') == 'library' &&
          _ids(c, 'installedBy').contains(component['id']) &&
          componentIsOffered(manifest, c, target),
    );
    if (installsLibrary &&
        (indexed == null ||
            sizeOf(withInstalled(component)) >
                sizeOf(withInstalled(indexed)))) {
      indexed = component;
    }
  }

  // בלי חבילה, "מלאה" היא התוכנה עם ספרייה — ובלי ספרייה אין "מלאה". ב-Android
  // גם "מלאה + אינדקס": בטלפון בניית האינדקס איטית מאוד.
  final List<String> full;
  var fullIndexed = indexed == null
      ? const <String>[]
      : [...withInstalled(indexed), ...offline];
  if (bundle != null) {
    full = [...withInstalled(bundle), ...offline];
  } else {
    final collected = _collect(
      manifest,
      target,
      types: const {'application', 'library', 'dependency'},
    );
    final hasLibrary = components.any(
      (c) => collected.contains(c['id']) && _field(c, 'type') == 'library',
    );
    full = hasLibrary ? [...collected, ...offline] : const [];
    if (hasLibrary && target.platform == 'android') {
      fullIndexed = [
        ...collected,
        ..._collect(manifest, target, types: const {'library-index'}),
        ...offline,
      ];
    }
  }

  final candidates = [
    (
      id: 'full-indexed',
      caption: 'התקנה מלאה + אינדקס חיפוש',
      description:
          'למחשב שאין בו אינטרנט — אינדקס החיפוש מוכן, והחיפוש עובד מיד. כולל חיפוש חכם.',
      members: fullIndexed,
    ),
    (
      id: 'full',
      caption: 'התקנה מלאה',
      description:
          'למחשב שאין בו אינטרנט — אינדקס החיפוש ייבנה בתוכנה, וזה לוקח זמן. כולל חיפוש חכם.',
      members: full,
    ),
    (
      id: 'basic',
      caption: 'התקנה בסיסית (מומלצת)',
      description: 'למחשב שיש בו אינטרנט — הספרייה תרד מתוך התוכנה.',
      members: [
        ..._collect(manifest, target, types: const {'application'}),
        ..._collect(manifest, target, requiredOnly: true),
      ],
    ),
    (
      id: 'update',
      caption: 'עדכון התוכנה בלבד',
      description: 'קובץ ההתקנה של הגרסה החדשה, לעדכון התקנה קיימת.',
      members: _collect(manifest, target, types: const {'application'}),
    ),
  ];

  final presets = <AssistantPreset>[];
  for (final candidate in candidates) {
    if (candidate.members.isEmpty) continue;
    final closed = withDependencies(manifest, candidate.members, target);
    if (closed.isEmpty) continue;
    if (presets.any((p) => _sameList(p.members, closed))) continue;
    presets.add(
      AssistantPreset(
        id: candidate.id,
        caption: candidate.caption,
        description: candidate.description,
        members: closed,
      ),
    );
  }
  return [
    for (final id in kPresetDisplayOrder) ...presets.where((p) => p.id == id),
  ];
}

/// מזהה ההצעה המסומנת מראש: [kDefaultPresetId], ובלעדיה `full` — לא
/// `full-indexed` הגדולה ממנה; בלי שתיהן — הראשונה. null כשאין הצעות.
String? defaultPresetIdFor(List<AssistantPreset> presets) {
  for (final id in const [kDefaultPresetId, 'full']) {
    if (presets.any((p) => p.id == id)) return id;
  }
  return presets.isEmpty ? null : presets.first.id;
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// האם נכס מפוצל מורכב לקובץ אחד בתיקיית היעד.
///
/// ל-Windows: רק exe מתחת ל-4 GiB — ארכיון נשאר חלקים, כי המתקין שצורך אותו
/// קורא את החלקים. לכל יעד אחר: כל נכס מתחת ל-4 GiB, כי שם המשתמש פורס אותו.
bool shouldAssembleSplitAsset(
  Map<String, Object?> asset,
  String targetPlatform,
) {
  final size = asset['size'] as int;
  if (size >= kMaxSingleOutputFileSize) return false;
  if (targetPlatform == 'windows') {
    return (asset['name'] as String).toLowerCase().endsWith('.exe');
  }
  return true;
}

/// שם תת-התיקייה כשנוצר יותר מקובץ אחד.
String outputSubfolderName(String targetPlatform) =>
    'אוצריא להתקנה ל-${kPlatformDisplayNames[targetPlatform] ?? targetPlatform}';

/// הקבצים שייווצרו בתיקיית היעד, בסדר המניפסט. קובץ של רכיב עם
/// `outputFolder` נכתב בתיקייה הזאת, והנתיב היחסי מופרד ב-`/`.
List<String> plannedOutputFiles(
  Map<String, Object?> manifest,
  Iterable<String> selectedIds,
  AssistantTarget target,
) {
  final selected = selectedIds.toSet();
  final files = <String>[];
  for (final component in _components(manifest)) {
    if (!selected.contains(component['id'])) continue;
    final folder = _field(component, 'outputFolder');
    final prefix = folder.isEmpty ? '' : '$folder/';
    for (final asset
        in (component['assets'] as List).cast<Map<String, Object?>>()) {
      if (asset['kind'] == 'split' &&
          !shouldAssembleSplitAsset(asset, target.platform)) {
        files.addAll(
          (asset['parts'] as List).cast<Map<String, Object?>>().map(
            (part) => '$prefix${part['name']}',
          ),
        );
      } else {
        files.add('$prefix${asset['name']}');
      }
    }
  }
  return files;
}

/// התיקייה היחסית לתיקיית הבסיס: '' לקובץ יחיד, אחרת תת-התיקייה.
String plannedOutputSubfolder(List<String> files, String targetPlatform) =>
    files.length > 1 ? outputSubfolderName(targetPlatform) : '';

/// ההסברים (`outputNote`) שעמוד הסיום מוסיף לבחירה, בסדר המניפסט ובלי כפולים.
List<String> plannedOutputNotes(
  Map<String, Object?> manifest,
  Iterable<String> selectedIds, {
  bool english = false,
}) {
  final selected = selectedIds.toSet();
  final notes = <String>[];
  for (final component in _components(manifest)) {
    if (!selected.contains(component['id'])) continue;
    final note = componentText(component, 'outputNote', english: english);
    if (note.isNotEmpty && !notes.contains(note)) notes.add(note);
  }
  return notes;
}

// ============================ מחברי זמננו ============================
//
// מסד ספרים רשמי שהמסייע מוריד בנוסף לבחירה, רק כשהמשתמש סימן זאת. המקור
// הוא ה-release האחרון של [kZmanenuRepository] — לא המניפסט של אוצריא —
// ולכן כשאין release (404 מה-API) או שאין בו חבילה, האפשרות אינה מוצגת.

const String kZmanenuRepository = 'Otzaria/zmanenu-library';

/// שם החבילה הלא-מקוונת; האפליקציה מזהה אותה בשם הזה (`offlinePackageName`).
const String kZmanenuArchiveName = 'zmanenu-offline.tar.zst';

/// מניפסט החלקים של `split_release_asset.sh`.
const String kZmanenuPartsManifestName = '$kZmanenuArchiveName.manifest.json';

/// תיקיית האיסוף, יחסית לתיקיית הנתונים של אוצריא
/// (`AttachedLibraryUpdateService.defaultDropDirectory`).
const String kZmanenuDropFolder = 'מסדים אישיים/להתקנה';

/// היעדים שבהם האפליקציה מתקינה את החבילה מתיקייה. ב-Android בחירת התיקייה
/// עוברת דרך SAF, שאינה מוסרת נתיב, והחבילה לא הייתה מותקנת.
const Set<String> kZmanenuPlatforms = {'windows', 'macos', 'linux'};

const String kZmanenuReleaseApiUrl =
    'https://api.github.com/repos/$kZmanenuRepository/releases/latest';

bool zmanenuIsOffered(AssistantTarget target) =>
    kZmanenuPlatforms.contains(target.platform);

final RegExp _safeName = RegExp(r'^[A-Za-z0-9._+-]+$');
final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

bool _isSafeName(String value) =>
    _safeName.hasMatch(value) && value != '.' && value != '..';

/// כתובת נכס. [tag] ריק — ה-API לא ענה, והכתובת היא של ה-release האחרון.
String zmanenuAssetUrl(String tag, String name) => tag.isEmpty
    ? 'https://github.com/$kZmanenuRepository/releases/latest/download/$name'
    : 'https://github.com/$kZmanenuRepository/releases/download/$tag/$name';

/// [sha256] ריק — קובץ שלם בלי hash ידוע: המסייע אינו מאמת אותו ואינו לוקח
/// אותו מהמטמון, והאפליקציה מאמתת חתימה ו-sha256 בייבוא. [size] 0 — לא ידוע.
typedef ZmanenuFile = ({String name, int size, String sha256, String url});

/// מה שיורד. [split] — חלקים, ואחריהם נכתב מניפסט החלקים שכבר נקרא.
class ZmanenuOffer {
  const ZmanenuOffer({
    required this.tag,
    required this.downloads,
    required this.split,
  });

  final String tag;
  final List<ZmanenuFile> downloads;
  final bool split;

  int get downloadSize => downloads.fold(0, (sum, f) => sum + f.size);

  /// הקבצים בתיקיית היעד, בסדר הכתיבה: מניפסט החלקים אחרון, כדי שהאפליקציה
  /// לא תמצא חבילה חלקית.
  List<String> get outputFiles => [
    for (final file in downloads) file.name,
    if (split) kZmanenuPartsManifestName,
  ];

  Map<String, Object> toJson() => {
    'tag': tag,
    'split': split,
    'downloadSize': downloadSize,
    'downloads': [
      for (final f in downloads)
        {'name': f.name, 'size': f.size, 'sha256': f.sha256, 'url': f.url},
    ],
    'outputFiles': outputFiles,
  };
}

List<Map<String, Object?>> _releaseAssets(Map<String, Object?> release) =>
    ((release['assets'] as List?) ?? const []).cast<Map<String, Object?>>();

/// ה-sha256 מתוך `digest` של נכס ב-API (`sha256:<hex>`), או null.
String? _assetSha256(Map<String, Object?> asset) {
  final digest = asset['digest'];
  if (digest is! String || !digest.startsWith('sha256:')) return null;
  final hex = digest.substring('sha256:'.length);
  return _sha256Hex.hasMatch(hex) ? hex : null;
}

/// הנכס של הארכיון השלם; [verified] — רק עם sha256 ב-`digest`.
Map<String, Object?>? _wholeAsset(
  Map<String, Object?> release, {
  bool verified = true,
}) {
  for (final asset in _releaseAssets(release)) {
    if (asset['name'] != kZmanenuArchiveName) continue;
    final size = asset['size'];
    if (size is int && size > 0 && (!verified || _assetSha256(asset) != null)) {
      return asset;
    }
  }
  return null;
}

/// התג של release מה-API; null כשאינו בטוח לנתיב.
String? _releaseTag(Map<String, Object?> release) {
  final tag = release['tag_name'];
  return tag is String && _isSafeName(tag) ? tag : null;
}

/// מאיפה לקרוא את מניפסט החלקים, או null כשאין צורך או שאין כזה.
/// [release] — תשובת `releases/latest` של ה-API; null כשה-API לא ענה (מגבלת
/// קצב, חסימה) — אז הכתובת הישירה של ה-release האחרון, כמו בספרייה.
String? zmanenuPartsManifestUrl(Map<String, Object?>? release) {
  if (release == null) return zmanenuAssetUrl('', kZmanenuPartsManifestName);
  final tag = _releaseTag(release);
  if (tag == null || _wholeAsset(release) != null) return null;
  final listed = _releaseAssets(
    release,
  ).any((a) => a['name'] == kZmanenuPartsManifestName);
  return listed ? zmanenuAssetUrl(tag, kZmanenuPartsManifestName) : null;
}

/// ההורדה של מחברי זמננו, או null כשאין מה להציע.
///
/// קובץ שלם עם sha256 מה-API; אחרת חלקים לפי מניפסט החלקים ([partsManifest],
/// שנקרא מ-[zmanenuPartsManifestUrl]); ובלי מניפסט חלקים — הקובץ השלם בלי
/// sha256 (מה-API, או בלי ה-API מה-release האחרון, בגודל לא ידוע). המסייע
/// אינו פורס את החבילה ואינו בודק את החתימה שבתוכה: האפליקציה עושה זאת בייבוא.
ZmanenuOffer? zmanenuOffer(
  Map<String, Object?>? release, {
  Map<String, Object?>? partsManifest,
}) {
  var tag = '';
  if (release != null) {
    final releaseTag = _releaseTag(release);
    if (releaseTag == null) return null;
    tag = releaseTag;
    if (_wholeAsset(release) case final whole?) {
      return _wholeOffer(tag, whole['size'] as int, _assetSha256(whole)!);
    }
  }
  if (partsManifest == null) {
    if (release == null) return _wholeOffer(tag, 0, '');
    final unverified = _wholeAsset(release, verified: false);
    return unverified == null
        ? null
        : _wholeOffer(tag, unverified['size'] as int, '');
  }
  if (partsManifest['archive'] != kZmanenuArchiveName) return null;
  final parts = partsManifest['parts'];
  if (parts is! List || parts.isEmpty) return null;
  final listed = release == null
      ? null
      : {for (final a in _releaseAssets(release)) a['name']: a['size']};
  final downloads = <ZmanenuFile>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part is! Map) return null;
    final name = part['name'];
    final size = part['size'];
    final sha = part['sha256'];
    if (name != '$kZmanenuArchiveName.part-${i.toString().padLeft(3, '0')}' ||
        size is! int ||
        size <= 0 ||
        sha is! String ||
        !_sha256Hex.hasMatch(sha)) {
      return null;
    }
    // החלק חייב להיות נכס באותו release ובאותו גודל.
    if (listed != null && listed[name] != size) return null;
    downloads.add((
      name: name as String,
      size: size,
      sha256: sha,
      url: zmanenuAssetUrl(tag, name),
    ));
  }
  final total = partsManifest['size'];
  if (total is! int || total != downloads.fold(0, (s, f) => s + f.size)) {
    return null;
  }
  return ZmanenuOffer(tag: tag, downloads: downloads, split: true);
}

ZmanenuOffer _wholeOffer(String tag, int size, String sha256) => ZmanenuOffer(
  tag: tag,
  split: false,
  downloads: [
    (
      name: kZmanenuArchiveName,
      size: size,
      sha256: sha256,
      url: zmanenuAssetUrl(tag, kZmanenuArchiveName),
    ),
  ],
);

/// הקבצים בתיקיית היעד כשמחברי זמננו יורדים למחשב אחר: לצד קובצי הבחירה,
/// באותה תיקייה, ולכן הם נספרים בכלל "יותר מקובץ אחד → תת-תיקייה". למחשב
/// הזה הם נכתבים לתיקיית האיסוף ואינם משנים את תיקיית הפלט.
List<String> plannedOutputFilesWithZmanenu(
  Map<String, Object?> manifest,
  Iterable<String> selectedIds,
  AssistantTarget target,
  ZmanenuOffer offer,
) => [
  ...plannedOutputFiles(manifest, selectedIds, target),
  if (zmanenuIsOffered(target)) ...offer.outputFiles,
];
