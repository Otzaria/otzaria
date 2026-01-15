import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Service for handling URL communication between app instances
class UrlHandlerService {
  static const String _urlFileName = 'pending_url.txt';
  static File? _urlFile;
  static Timer? _monitoringTimer;
  static Function(String)? _urlHandler;
  
  /// Initialize the URL handler service
  static Future<void> initialize() async {
    try {
      // Use the same directory as SimpleSingleInstance
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
      
      debugPrint('UrlHandlerService: Initialized with file: ${_urlFile!.path}');
      
      // Clean up any existing URL file
      if (_urlFile!.existsSync()) {
        await _urlFile!.delete();
        debugPrint('UrlHandlerService: Cleaned up existing URL file');
      }
      
      // Start monitoring for URL files
      _startMonitoring();
    } catch (e) {
      debugPrint('UrlHandlerService: Failed to initialize: $e');
    }
  }
  
  /// Set the URL handler function
  static void setUrlHandler(Function(String) handler) {
    _urlHandler = handler;
    debugPrint('UrlHandlerService: URL handler set');
  }
  
  /// Write a URL to be handled by the running instance
  static Future<void> writeUrlForRunningInstance(String url) async {
    try {
      if (_urlFile == null) {
        debugPrint('UrlHandlerService: URL file not initialized');
        return;
      }
      
      final urlData = {
        'url': url,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await _urlFile!.writeAsString(jsonEncode(urlData));
      debugPrint('UrlHandlerService: Wrote URL for running instance: $url');
    } catch (e) {
      debugPrint('UrlHandlerService: Failed to write URL: $e');
    }
  }
  
  /// Start monitoring for URL files from other instances
  static void _startMonitoring() {
    if (_urlFile == null) return;
    
    debugPrint('UrlHandlerService: Starting monitoring');
    
    // Check for pending URLs every 500ms
    _monitoringTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        if (!_urlFile!.existsSync()) return;
        
        final content = await _urlFile!.readAsString();
        final urlData = jsonDecode(content) as Map<String, dynamic>;
        final url = urlData['url'] as String;
        final timestamp = urlData['timestamp'] as int;
        
        // Only process URLs that are less than 10 seconds old
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - timestamp > 10000) {
          await _urlFile!.delete();
          debugPrint('UrlHandlerService: Deleted expired URL file');
          return;
        }
        
        debugPrint('UrlHandlerService: Found pending URL: $url');
        
        // Delete the file first to avoid processing it again
        await _urlFile!.delete();
        
        // Handle the URL if handler is set
        if (_urlHandler != null) {
          debugPrint('UrlHandlerService: Calling URL handler');
          _urlHandler!(url);
        } else {
          debugPrint('UrlHandlerService: No URL handler set');
        }
        
      } catch (e) {
        debugPrint('UrlHandlerService: Error monitoring URL file: $e');
        // Try to delete corrupted file
        try {
          if (_urlFile!.existsSync()) {
            await _urlFile!.delete();
          }
        } catch (_) {}
      }
    });
  }
  
  /// Stop monitoring (for cleanup)
  static void dispose() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _urlHandler = null;
    debugPrint('UrlHandlerService: Disposed');
  }
}