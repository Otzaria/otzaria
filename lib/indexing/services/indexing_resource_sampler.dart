import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/diagnostics/memory_info.dart';
import 'package:otzaria/indexing/models/indexing_resource_policy.dart';

class IndexingResourceSampler {
  static Future<IndexingResourcePolicy>? _pending;

  static Future<IndexingResourcePolicy> sample() {
    // A timeout does not end Isolate.run; retain it to avoid overlapping probes.
    final pending = _pending ??= Isolate.run(_read).whenComplete(() {
      _pending = null;
    });
    return pending
        .timeout(
          const Duration(seconds: 1),
          onTimeout: IndexingResourcePolicy.conservative,
        )
        .catchError((Object error) {
          debugPrint('Indexing resource sample unavailable: $error');
          return IndexingResourcePolicy.conservative();
        });
  }

  static IndexingResourcePolicy _read() {
    final memory = memoryInfo();
    var cores = Platform.numberOfProcessors;
    var total = memory['totalRamMb'];
    var available = memory['availableRamMb'];
    if (Platform.isLinux) {
      final quota = _optionalFile('/sys/fs/cgroup/cpu.max')?.split(' ');
      if (quota != null && quota.length == 2) {
        final micros = int.tryParse(quota[0]);
        final period = int.tryParse(quota[1]);
        if (micros != null && period != null && period > 0) {
          cores = (micros ~/ period).clamp(1, cores);
        }
      }
      final limit = int.tryParse(
        _optionalFile('/sys/fs/cgroup/memory.max') ?? '',
      );
      final current = int.tryParse(
        _optionalFile('/sys/fs/cgroup/memory.current') ?? '',
      );
      if (limit != null && limit > 0) {
        final limitedMb = limit >> 20;
        if (total == null || limitedMb < total) total = limitedMb;
        if (current != null) {
          final freeMb = ((limit - current) >> 20).clamp(0, limitedMb);
          if (available == null || freeMb < available) available = freeMb;
        }
      }
    }
    return IndexingResourcePolicy(
      cpuCount: cores,
      mobile: Platform.isAndroid || Platform.isIOS,
      totalRamMb: total,
      availableRamMb: available,
    );
  }

  static String? _optionalFile(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }
}
