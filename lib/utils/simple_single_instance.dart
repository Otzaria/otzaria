import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Simple single instance manager using file locks
class SimpleSingleInstance {
  static const String _lockFileName = 'otzaria_instance.lock';
  static const String _urlFileName = 'pending_url.txt';
  static File? _lockFile;
  static File? _urlFile;
  
  /// Check if this is the first instance
  static Future<bool> isFirstInstance() async {
    try {
      // Use a more reliable directory for Windows
      final Directory appDir;
      if (Platform.isWindows) {
        final tempDir = Directory.systemTemp;
        appDir = Directory('${tempDir.path}\\otzaria_locks');
        if (!appDir.existsSync()) {
          appDir.createSync(recursive: true);
        }
      } else {
        appDir = await getApplicationSupportDirectory();
      }
      
      _lockFile = File('${appDir.path}${Platform.pathSeparator}$_lockFileName');
      _urlFile = File('${appDir.path}${Platform.pathSeparator}$_urlFileName');
      
      debugPrint('SimpleSingleInstance: Lock file: ${_lockFile!.path}');
      
      if (_lockFile!.existsSync()) {
        // Check if the process in the lock file is still running
        final lockContent = await _lockFile!.readAsString();
        final lockData = jsonDecode(lockContent) as Map<String, dynamic>;
        final pid = lockData['pid'] as int;
        final timestamp = lockData['timestamp'] as int;
        
        // Check if lock is too old (more than 1 hour)
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - timestamp > 3600000) {
          debugPrint('SimpleSingleInstance: Lock file is too old, removing');
          await _lockFile!.delete();
          return true;
        }
        
        // Check if process is still running (cross-platform)
        try {
          bool isRunning;
          if (Platform.isWindows) {
            // Windows: use tasklist
            final result = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
            final output = result.stdout.toString();
            debugPrint('SimpleSingleInstance: tasklist output: $output');
            isRunning = output.contains('"$pid"') && !output.contains('INFO: No tasks');
          } else if (Platform.isLinux || Platform.isMacOS) {
            // Linux/macOS: use ps
            final result = await Process.run('ps', ['-p', pid.toString()]);
            isRunning = result.exitCode == 0;
            debugPrint('SimpleSingleInstance: ps exit code: ${result.exitCode}');
          } else {
            // Other platforms: assume not running
            debugPrint('SimpleSingleInstance: Unsupported platform, assuming process not running');
            isRunning = false;
          }
          
          if (isRunning) {
            debugPrint('SimpleSingleInstance: Process $pid is still running');
            return false;
          } else {
            debugPrint('SimpleSingleInstance: Process $pid is not running, removing lock');
            await _lockFile!.delete();
            return true;
          }
        } catch (e) {
          debugPrint('SimpleSingleInstance: Error checking process: $e');
          // If we can't check, assume it's not running and allow this instance
          debugPrint('SimpleSingleInstance: Assuming process is not running due to error');
          try {
            await _lockFile!.delete();
          } catch (_) {}
          return true;
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('SimpleSingleInstance: Error in isFirstInstance: $e');
      return true; // Default to allowing the instance
    }
  }
  
  /// Create lock file for this instance
  static Future<void> createLock() async {
    try {
      if (_lockFile == null) return;
      
      final lockData = {
        'pid': pid,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await _lockFile!.writeAsString(jsonEncode(lockData));
      debugPrint('SimpleSingleInstance: Created lock file with PID: $pid');
    } catch (e) {
      debugPrint('SimpleSingleInstance: Error creating lock: $e');
    }
  }
  
  /// Write URL for the running instance
  static Future<void> writeUrlForRunningInstance(String url) async {
    try {
      // Make sure we have the URL file path
      if (_urlFile == null) {
        // Initialize the file path if not already done
        final Directory appDir;
        if (Platform.isWindows) {
          final tempDir = Directory.systemTemp;
          appDir = Directory('${tempDir.path}\\otzaria_locks');
          if (!appDir.existsSync()) {
            appDir.createSync(recursive: true);
          }
        } else {
          appDir = await getApplicationSupportDirectory();
        }
        _urlFile = File('${appDir.path}${Platform.pathSeparator}$_urlFileName');
      }
      
      final urlData = {
        'url': url,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await _urlFile!.writeAsString(jsonEncode(urlData));
      debugPrint('SimpleSingleInstance: Wrote URL for running instance: $url');
    } catch (e) {
      debugPrint('SimpleSingleInstance: Error writing URL: $e');
    }
  }
  
  /// Wait for URL processing by first instance (handshake protocol)
  /// Returns when the URL file is deleted by the first instance or timeout occurs
  static Future<void> waitForUrlProcessing() async {
    if (_urlFile == null) return;
    
    const int maxWaitTimeMs = 5000; // 5 seconds timeout
    const int checkIntervalMs = 100; // Check every 100ms
    int elapsedMs = 0;
    
    debugPrint('SimpleSingleInstance: Waiting for URL processing (handshake)');
    
    while (elapsedMs < maxWaitTimeMs) {
      try {
        // If file no longer exists, it was processed
        if (!_urlFile!.existsSync()) {
          debugPrint('SimpleSingleInstance: URL file deleted - processing complete');
          return;
        }
        
        // Wait before next check
        await Future.delayed(const Duration(milliseconds: checkIntervalMs));
        elapsedMs += checkIntervalMs;
        
      } catch (e) {
        debugPrint('SimpleSingleInstance: Error during handshake wait: $e');
        break;
      }
    }
    
    // Timeout occurred
    debugPrint('SimpleSingleInstance: Handshake timeout after ${maxWaitTimeMs}ms');
  }
  
  /// Clean up lock file
  static Future<void> cleanup() async {
    try {
      if (_lockFile != null && _lockFile!.existsSync()) {
        await _lockFile!.delete();
        debugPrint('SimpleSingleInstance: Cleaned up lock file');
      }
    } catch (e) {
      debugPrint('SimpleSingleInstance: Error cleaning up: $e');
    }
  }
}