import 'dart:async';

import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מדמה את מקור השורות של המנוע: resume בלי suspend תואם נדחה, כמו במנוע.
class FakeLineSourceEngine implements LineSourceEngine {
  int depth = 0;
  int suspends = 0;
  int resumes = 0;
  int registrations = 0;
  bool hostReady = false;
  BigInt libraryFallbacks = BigInt.zero;
  bool readyAfterRegistration = true;
  Object? failSuspendWith;
  Object? failRegistrationWith;
  final configuredPaths = <String>[];
  Completer<void>? suspendGate;

  @override
  Future<LineSourceStatus> status() async => LineSourceStatus(
    configured: configuredPaths.isNotEmpty,
    open: false,
    suspendDepth: depth,
    hostApiReady: hostReady,
    generation: BigInt.zero,
    libraryFallbacks: libraryFallbacks,
  );

  @override
  Future<void> configure(String dbPath) async => configuredPaths.add(dbPath);

  @override
  Future<void> suspend() async {
    final failure = failSuspendWith;
    if (failure != null) throw failure;
    await suspendGate?.future;
    suspends++;
    depth++;
  }

  @override
  Future<void> resume() async {
    if (depth == 0) throw Exception('resume without a matching suspend');
    resumes++;
    depth--;
  }

  @override
  Future<void> registerHostSqlite() async {
    registrations++;
    final failure = failRegistrationWith;
    if (failure != null) throw failure;
    hostReady = readyAfterRegistration;
  }
}
