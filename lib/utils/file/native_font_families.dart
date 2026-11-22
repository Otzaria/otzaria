import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// שם הערוץ והשיטה מול הקוד הנייטיבי ב-iOS (`ios/Runner/AppDelegate.swift`).
const String nativeFontFamiliesChannelName = 'otzaria/native_fonts';
const String nativeFontFamiliesMethod = 'hebrewFamilies';

/// משפחת גופן של מערכת ההפעלה שהאפליקציה מכירה רק בשמה, בלי קובץ.
@immutable
class NativeFontFamily {
  final String family;

  /// האם הגופן ממפה את טעמי המקרא (U+0591). דגל חסר נחשב "תומך": אזהרה
  /// שגויה גרועה מהחמצה.
  final bool supportsTaamim;

  const NativeFontFamily(this.family, {this.supportsTaamim = true});
}

/// מקור שמות משפחות הגופנים של המערכת. ממשק, כדי שבדיקות יחליפו אותו ב-fake
/// בלי ערוץ פלטפורמה.
abstract interface class NativeFontFamilySource {
  /// משפחות המערכת שיש בהן אותיות עבריות. ריק כשאין או כשהקריאה נכשלה.
  Future<List<NativeFontFamily>> hebrewFamilies();
}

/// המימוש האמיתי: [MethodChannel] שה-Swift ב-iOS עונה לו.
class ChannelNativeFontFamilySource implements NativeFontFamilySource {
  const ChannelNativeFontFamilySource();

  static const MethodChannel _channel = MethodChannel(
    nativeFontFamiliesChannelName,
  );

  @override
  Future<List<NativeFontFamily>> hebrewFamilies() async {
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>(nativeFontFamiliesMethod);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
    if (raw is! List) return const [];
    final seen = <String>{};
    final result = <NativeFontFamily>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['family'];
      if (name is! String) continue;
      final family = name.trim();
      if (family.isEmpty || !seen.add(family.toLowerCase())) continue;
      result.add(
        NativeFontFamily(family, supportsTaamim: entry['taamim'] != false),
      );
    }
    return result;
  }
}
