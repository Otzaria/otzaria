import 'package:flutter/material.dart';

/// Configuration class for ShamorZachor widget
class ShamorZachorConfig {
  /// Optional asset path override for data files
  final String? assetsBasePath;

  /// Optional theme data to inherit from host app
  final ThemeData? themeData;

  /// Optional text direction override
  final TextDirection? textDirection;

  /// Optional locale override
  final Locale? locale;

  const ShamorZachorConfig({
    this.assetsBasePath,
    this.themeData,
    this.textDirection,
    this.locale,
  });

  /// Default configuration with sensible defaults
  static const ShamorZachorConfig defaultConfig = ShamorZachorConfig();
}
