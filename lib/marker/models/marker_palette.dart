import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:otzaria/marker/models/marker_text.dart';
import 'package:otzaria/theme/marker_colors.dart';

/// אופן הציור של סימון. [wireName] הוא הערך ש-`PluginHighlightStyle.markerMode`
/// מצפה לו, וגם הערך שנשמר בפלטה של התוסף הישן.
enum MarkerStyleMode {
  background('text-background'),
  underline('underline'),
  box('box'),
  text('line-marker');

  const MarkerStyleMode(this.wireName);

  final String wireName;

  static MarkerStyleMode fromWire(Object? value) => MarkerStyleMode.values
      .firstWhere((mode) => mode.wireName == value, orElse: () => background);
}

class MarkerColor extends Equatable {
  static const int maxLabelLength = 24;
  static const double minOpacity = 0.15;
  static const double maxBorderRadius = 16;

  final String id;
  final String label;

  /// `#RRGGBB` באותיות גדולות.
  final String hex;
  final bool enabled;
  final double opacity;
  final MarkerStyleMode mode;
  final double borderRadius;

  const MarkerColor({
    required this.id,
    required this.label,
    required this.hex,
    this.enabled = true,
    this.opacity = MarkerColors.defaultOpacity,
    this.mode = MarkerStyleMode.background,
    this.borderRadius = 3,
  });

  MarkerColor copyWith({
    String? label,
    String? hex,
    bool? enabled,
    double? opacity,
    MarkerStyleMode? mode,
    double? borderRadius,
  }) => MarkerColor(
    id: id,
    label: label ?? this.label,
    hex: hex ?? this.hex,
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
    mode: mode ?? this.mode,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  /// ערך ARGB של הצבע, אטום.
  int get argb => argbOf(hex);

  /// ARGB אטום של `#RRGGBB`.
  static int argbOf(String hex) =>
      0xFF000000 | int.parse(hex.substring(1), radix: 16);

  /// `#RRGGBB` של צבע, בלי השקיפות.
  static String hexOf(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'hex': hex,
    'enabled': enabled,
    'opacity': opacity,
    'markerMode': mode.wireName,
    'borderRadius': borderRadius,
  };

  /// מקבל גם את רשומת הצבע של התוסף הישן; ערכים לא תקינים מוחלפים בברירת מחדל.
  static MarkerColor? fromJson(Object? json, {String? fallbackHex}) {
    if (json is! Map) return null;
    final id = normalizeId(json['id']);
    final hex = normalizeHex(json['hex']) ?? fallbackHex;
    if (id == null || hex == null) return null;
    final opacity = json['opacity'];
    final radius = json['borderRadius'];
    return MarkerColor(
      id: id,
      label: normalizeLabel(json['label']),
      hex: hex,
      enabled: json['enabled'] != false,
      opacity: opacity is num
          ? opacity.toDouble().clamp(minOpacity, 1).toDouble()
          : MarkerColors.defaultOpacity,
      mode: MarkerStyleMode.fromWire(json['markerMode']),
      borderRadius: radius is num
          ? radius.toDouble().clamp(0, maxBorderRadius).roundToDouble()
          : 3,
    );
  }

  static final _hexPattern = RegExp(r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$');

  /// `#RRGGBB` מתוך `#RRGGBB` או `#RRGGBBAA`; null לערך לא תקין.
  static String? normalizeHex(Object? value) {
    if (value is! String) return null;
    final match = _hexPattern.firstMatch(value.trim());
    return match == null ? null : '#${match.group(1)!.toUpperCase()}';
  }

  static String? normalizeId(Object? value) {
    if (value is! String) return null;
    final id = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    if (id.isEmpty) return null;
    return id.length > 59 ? id.substring(0, 59) : id;
  }

  static String normalizeLabel(Object? value) {
    final text = value is String
        ? value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').trim()
        : '';
    if (text.isEmpty) return 'צבע';
    return text.length > maxLabelLength
        ? truncateGraphemes(text, maxLabelLength)
        : text;
  }

  @override
  List<Object?> get props => [
    id,
    label,
    hex,
    enabled,
    opacity,
    mode,
    borderRadius,
  ];
}

/// פלטת המרקר: הסדר הוא סדר התפריט, ורק [maxMenuColors] הראשונים מבין
/// המופעלים מוצגים בו.
class MarkerPalette extends Equatable {
  static const int maxColors = 12;
  static const int maxMenuColors = 8;

  final List<MarkerColor> colors;
  final String defaultColorId;

  const MarkerPalette._(this.colors, this.defaultColorId);

  factory MarkerPalette({
    required List<MarkerColor> colors,
    String? defaultColorId,
  }) {
    final unique = <MarkerColor>[];
    final seen = <String>{};
    for (final color in colors) {
      if (unique.length == maxColors) break;
      var id = color.id;
      for (var n = 2; !seen.add(id); n++) {
        id = '${color.id}-$n';
      }
      unique.add(
        id == color.id
            ? color
            : MarkerColor(
                id: id,
                label: color.label,
                hex: color.hex,
                enabled: color.enabled,
                opacity: color.opacity,
                mode: color.mode,
                borderRadius: color.borderRadius,
              ),
      );
    }
    if (unique.isEmpty) return MarkerPalette.defaults();
    final enabled = unique.where((color) => color.enabled);
    final resolvedDefault = enabled.any((color) => color.id == defaultColorId)
        ? defaultColorId!
        : (enabled.isEmpty ? unique.first.id : enabled.first.id);
    return MarkerPalette._(List.unmodifiable(unique), resolvedDefault);
  }

  factory MarkerPalette.defaults() => MarkerPalette._(
    List.unmodifiable([
      for (final entry in MarkerColors.defaults)
        MarkerColor(
          id: entry.id,
          label: entry.label,
          hex: MarkerColor.hexOf(entry.color.toARGB32()),
          enabled: entry.enabled,
        ),
    ]),
    MarkerColors.defaults.first.id,
  );

  MarkerPalette copyWithDefault(String colorId) =>
      MarkerPalette(colors: colors, defaultColorId: colorId);

  List<MarkerColor> get menuColors =>
      colors.where((color) => color.enabled).take(maxMenuColors).toList();

  MarkerColor get defaultColor =>
      colors.firstWhere((color) => color.id == defaultColorId);

  MarkerColor? colorById(String id) {
    for (final color in colors) {
      if (color.id == id) return color;
    }
    return null;
  }

  String encode() => jsonEncode({
    'colors': [for (final color in colors) color.toJson()],
    'defaultColorId': defaultColorId,
  });

  /// פלטה שמורה, או ברירת המחדל כשאין או כשהערך פגום.
  static MarkerPalette decode(String? raw) {
    if (raw == null || raw.isEmpty) return MarkerPalette.defaults();
    try {
      return fromJson(jsonDecode(raw));
    } on FormatException {
      return MarkerPalette.defaults();
    }
  }

  /// מקבל גם את אובייקט ההגדרות של התוסף הישן (`colors`, `defaultColorId`).
  static MarkerPalette fromJson(Object? json) {
    if (json is! Map || json['colors'] is! List) {
      return MarkerPalette.defaults();
    }
    final defaults = MarkerPalette.defaults().colors;
    final colors = <MarkerColor>[];
    final raw = json['colors'] as List;
    for (var i = 0; i < raw.length; i++) {
      final color = MarkerColor.fromJson(
        raw[i],
        fallbackHex: i < defaults.length ? defaults[i].hex : null,
      );
      if (color != null) colors.add(color);
    }
    final defaultId = json['defaultColorId'];
    return MarkerPalette(
      colors: colors,
      defaultColorId: defaultId is String ? defaultId : null,
    );
  }

  @override
  List<Object?> get props => [colors, defaultColorId];
}
