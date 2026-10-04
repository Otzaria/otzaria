import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pinenacl/ed25519.dart' as ed;

/// זהות אנונימית של ההתקנה: זוג מפתחות ed25519 ומצב הרישום מול השרת.
class SearchFeedbackIdentity {
  SearchFeedbackIdentity.fromSeed(
    List<int> seed, {
    this.registeredKeyId,
    this.blocked = false,
  }) : _seed = Uint8List.fromList(seed),
       _signingKey = ed.SigningKey.fromSeed(Uint8List.fromList(seed)) {
    if (seed.length != seedLength) {
      throw const FormatException('seed must be 32 bytes');
    }
  }

  /// זהות חדשה מזרע אקראי.
  factory SearchFeedbackIdentity.generate([Random? random]) {
    final rng = random ?? Random.secure();
    return SearchFeedbackIdentity.fromSeed([
      for (var i = 0; i < seedLength; i++) rng.nextInt(256),
    ]);
  }

  static const int seedLength = 32;

  final Uint8List _seed;
  final ed.SigningKey _signingKey;

  /// ה-keyId שהשרת אישר ברישום; null = טרם נרשם.
  String? registeredKeyId;

  /// השרת חסם את המפתח — לא אוספים ולא שולחים עד איפוס המפתח.
  bool blocked;

  bool get isRegistered => registeredKeyId == keyId;

  Uint8List get publicKey => _signingKey.verifyKey.asTypedList;

  String get publicKeyBase64 => base64.encode(publicKey);

  String get keyId => keyIdOf(publicKey);

  /// base64url בלי ריפוד של SHA-256 על המפתח הציבורי הגולמי (43 תווים).
  static String keyIdOf(List<int> publicKey) =>
      base64Url.encode(sha256.convert(publicKey).bytes).replaceAll('=', '');

  /// חתימה (base64 רגיל, עם ריפוד) על הבתים המדויקים של [message].
  String sign(List<int> message) => base64.encode(
    _signingKey.sign(Uint8List.fromList(message)).signature.asTypedList,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'seed': base64.encode(_seed),
    'registeredKeyId': registeredKeyId,
    'blocked': blocked,
  };

  /// null על קובץ פגום — המתקשר יוצר זהות חדשה.
  static SearchFeedbackIdentity? tryParse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final seed = base64.decode(json['seed'] as String);
      if (seed.length != seedLength) return null;
      return SearchFeedbackIdentity.fromSeed(
        seed,
        registeredKeyId: json['registeredKeyId'] as String?,
        blocked: json['blocked'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// שמירת הזהות כקובץ בתיקיית נתוני האפליקציה (לא בהגדרות).
class SearchFeedbackIdentityStore {
  SearchFeedbackIdentityStore(this._directory);

  static const String fileName = 'installation_key.json';

  final Future<Directory> Function() _directory;

  Future<File> _file() async =>
      File(p.join((await _directory()).path, fileName));

  Future<SearchFeedbackIdentity?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return SearchFeedbackIdentity.tryParse(await file.readAsString());
  }

  /// כתיבה לקובץ זמני והחלפה, כדי שקריסה באמצע לא תשאיר קובץ חתוך.
  Future<void> save(SearchFeedbackIdentity identity) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(identity.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<void> delete() async {
    final file = await _file();
    for (final target in [file, File('${file.path}.tmp')]) {
      if (await target.exists()) await target.delete();
    }
  }
}
