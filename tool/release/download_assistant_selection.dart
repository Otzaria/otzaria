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
