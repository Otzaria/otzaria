import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/memory_info.dart';

void main() {
  test('parseMemInfo reads total and available RAM in MB', () {
    const text =
        'MemTotal:       16303332 kB\n'
        'MemFree:          871232 kB\n'
        'MemAvailable:    8151666 kB\n';
    expect(parseMemInfo(text), {'totalRamMb': 15921, 'availableRamMb': 7960});
  });

  test('parseMemInfo omits missing fields', () {
    expect(parseMemInfo('MemTotal: 2048 kB\n'), {'totalRamMb': 2});
    expect(parseMemInfo(''), isEmpty);
  });

  test('memoryInfo reports RAM and process memory on desktop', () {
    final info = memoryInfo();
    expect(info['processPeakRssMb'], greaterThan(0));
    if (Platform.isWindows || Platform.isLinux) {
      expect(info['totalRamMb'], greaterThan(0));
      expect(info['availableRamMb'], lessThanOrEqualTo(info['totalRamMb']!));
    }
    if (Platform.isWindows) {
      expect(
        info['processPeakCommitMb'],
        greaterThanOrEqualTo(info['processCommitMb']!),
      );
    }
  });

  test('formatMemoryLine joins fields on one line', () {
    expect(
      formatMemoryLine({'totalRamMb': 8000, 'processPeakCommitMb': 3100}),
      'totalRamMb=8000 processPeakCommitMb=3100',
    );
  });
}
