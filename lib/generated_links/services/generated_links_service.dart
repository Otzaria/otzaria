import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:otzaria/generated_links/repository/generated_links_book_resolver.dart';
import 'package:otzaria/generated_links/repository/generated_links_cache_store.dart';
import 'package:otzaria/generated_links/rules/generated_link_rules_registry.dart';
import 'package:otzaria/generated_links/services/generated_links_processor.dart';
import 'package:otzaria/generated_links/services/generated_links_scheduler.dart';
import 'package:otzaria/generated_links/services/generated_links_work_gate.dart';

/// Singleton שמאחד את כל תשתית קישורי ה-generated-links.
///
/// יש לאתחל פעם אחת ב-startup דרך [GeneratedLinksService.init].
/// לאחר מכן הגישה היא דרך [GeneratedLinksService.instance].
class GeneratedLinksService {
  static GeneratedLinksService? _instance;

  /// מחזיר את ה-singleton לאחר [init]. אם טרם אותחל — מחזיר null.
  static GeneratedLinksService? get instance => _instance;

  final GeneratedLinksCacheStore cacheStore;
  final GeneratedLinksWorkGate workGate;
  final GeneratedLinksScheduler scheduler;

  GeneratedLinksService._({
    required this.cacheStore,
    required this.workGate,
    required this.scheduler,
  });

  /// אתחול ה-singleton. בטוח לקריאה מרובה — רק הראשונה תעשה משהו.
  static Future<void> init() async {
    if (_instance != null) return;

    final store = await GeneratedLinksCacheStore.create();
    final gate = GeneratedLinksWorkGate();
    final resolver = GeneratedLinksBookResolver();
    final processor = GeneratedLinksProcessor(resolver: resolver);

    final scheduler = GeneratedLinksScheduler(
      cacheStore: store,
      workGate: gate,
      rulesVersion: GeneratedLinkRulesRegistry.defaultRulesVersion,
      processBatch: processor.processBatch,
    );

    _instance = GeneratedLinksService._(
      cacheStore: store,
      workGate: gate,
      scheduler: scheduler,
    );

    if (kDebugMode) {
      debugPrint('[GeneratedLinksService] initialized');
    }
  }
}
