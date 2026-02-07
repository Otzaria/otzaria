import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> installLinuxPackage(File debFile) async {
  // Create install script in the same directory as the DEB file
  final scriptPath = p.join(p.dirname(debFile.path), 'install.sh');
  final scriptFile = File(scriptPath);

  // Write the install script
  await scriptFile.writeAsString('''#!/bin/bash
set -e
DEB_FILE="${debFile.absolute.path}"
echo "מתקין את אוצריה..."
pkexec apt install -y "\$DEB_FILE"
echo "✓ ההתקנה הושלמה בהצלחה!"
''');

  // Make it executable
  await Process.run('chmod', ['+x', scriptPath]);

  // Run the script in a terminal
  try {
    // Try different terminal emulators
    final terminals = [
      'x-terminal-emulator',
      'gnome-terminal',
      'konsole',
      'xterm'
    ];

    for (final terminal in terminals) {
      final result = await Process.run('which', [terminal]);
      if (result.exitCode == 0) {
        await Process.start(terminal, ['-e', scriptPath],
            mode: ProcessStartMode.detached);
        return;
      }
    }

    // Fallback: run directly with pkexec
    await Process.start(
        'pkexec', ['apt', 'install', '-y', debFile.absolute.path],
        mode: ProcessStartMode.detached);
  } catch (e) {
    throw Exception('Failed to launch installer: $e');
  }
}

/// Wrapper for launchInstaller that handles Linux DEB files specially
Future<void> Function() wrapLinuxInstaller(
  Future<void> Function() originalLaunchInstaller,
  String appName,
) {
  return () async {
    if (!Platform.isLinux) {
      return originalLaunchInstaller();
    }

    try {
      // Find the DEB file in downloads directory
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir == null) {
        return originalLaunchInstaller();
      }

      // Look for the DEB file
      final files = downloadDir.listSync();
      final debFile = files.firstWhere(
        (f) => f.path.contains(appName) && f.path.endsWith('.deb'),
        orElse: () => throw Exception('DEB file not found'),
      );

      await installLinuxPackage(File(debFile.path));
    } catch (e) {
      // Fallback to original behavior
      return originalLaunchInstaller();
    }
  };
}
