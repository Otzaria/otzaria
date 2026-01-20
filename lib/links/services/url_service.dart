/// שירות טיפול ב-URLs בין instances של האפליקציה
library;

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import '../core/link_handler.dart';

/// שירות לטיפול ב-URLs בין instances של האפליקציה
class UrlService {
  static const String _urlFileName = 'pending_url.txt';
  static File? _urlFile;
  static Timer? _monitoringTimer;
  static Function(String)? _urlHandler;
  
  /// אתחול השירות
  static Future<void> initialize() async {
    try {
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
      
      debugPrint('UrlService: Initialized with file: ${_urlFile!.path}');
      
      // ניקוי קובץ URL קיים
      if (_urlFile!.existsSync()) {
        await _urlFile!.delete();
        debugPrint('UrlService: Cleaned up existing URL file');
      }
      
      // התחלת מעקב
      _startMonitoring();
    } catch (e) {
      debugPrint('UrlService: Failed to initialize: $e');
    }
  }
  
  /// הגדרת handler ל-URLs
  static void setHandler(Function(String) handler) {
    _urlHandler = handler;
    debugPrint('UrlService: URL handler set');
  }
  
  /// כתיבת URL לטיפול על ידי instance פעיל
  static Future<void> writeForRunningInstance(String url) async {
    try {
      if (_urlFile == null) {
        debugPrint('UrlService: URL file not initialized');
        return;
      }
      
      final urlData = {
        'url': url,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await _urlFile!.writeAsString(jsonEncode(urlData));
      debugPrint('UrlService: Wrote URL for running instance: $url');
    } catch (e) {
      debugPrint('UrlService: Failed to write URL: $e');
    }
  }
  
  /// התחלת מעקב אחר קבצי URL
  static void _startMonitoring() {
    if (_urlFile == null) return;
    
    debugPrint('UrlService: Starting monitoring');
    
    _monitoringTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        if (!_urlFile!.existsSync()) return;
        
        final content = await _urlFile!.readAsString();
        final urlData = jsonDecode(content) as Map<String, dynamic>;
        final url = urlData['url'] as String;
        final timestamp = urlData['timestamp'] as int;
        
        // עיבוד URLs שהם פחות מ-10 שניות
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - timestamp > 10000) {
          await _urlFile!.delete();
          debugPrint('UrlService: Deleted expired URL file');
          return;
        }
        
        debugPrint('UrlService: Found pending URL: $url');
        
        // מחיקת הקובץ כדי למנוע עיבוד חוזר
        await _urlFile!.delete();
        
        // טיפול ב-URL
        if (_urlHandler != null) {
          debugPrint('UrlService: Calling URL handler');
          _urlHandler!(url);
        } else {
          debugPrint('UrlService: No URL handler set');
        }
        
      } catch (e) {
        debugPrint('UrlService: Error monitoring URL file: $e');
        try {
          if (_urlFile!.existsSync()) {
            await _urlFile!.delete();
          }
        } catch (_) {}
      }
    });
  }
  
  /// עצירת המעקב (לניקוי)
  static void dispose() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _urlHandler = null;
    debugPrint('UrlService: Disposed');
  }

  /// טיפול ב-URL ראשוני כשהאפליקציה נפתחת
  static void handleInitialUrl(
    BuildContext context,
    String url,
    VoidCallback? onComplete,
  ) {
    debugPrint('UrlService: Received initial URL: $url');
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        debugPrint('UrlService: Context not mounted, skipping URL handling');
        return;
      }
      
      final libraryBloc = context.read<LibraryBloc>();
      
      // אם הספרייה כבר נטענה, טפל ב-URL מיד
      if (libraryBloc.state.library != null && !libraryBloc.state.isLoading) {
        debugPrint('UrlService: Library already loaded, handling URL immediately');
        await _processUrl(context, url);
        onComplete?.call();
        return;
      }
      
      // אחרת, חכה שהספרייה תיטען
      debugPrint('UrlService: Waiting for library to load...');
      
      try {
        await libraryBloc.stream.firstWhere(
          (state) => state.library != null && !state.isLoading,
        );
        
        debugPrint('UrlService: Library loaded, handling URL now');
        if (context.mounted) {
          await _processUrl(context, url);
          onComplete?.call();
        } else {
          debugPrint('UrlService: Context unmounted after library load');
        }
      } catch (e) {
        debugPrint('UrlService: Error waiting for library: $e');
      }
    });
  }
  
  /// עיבוד URL לאחר שהספרייה נטענה
  static Future<void> _processUrl(BuildContext context, String url) async {
    debugPrint('UrlService: Starting URL processing for: $url');
    
    try {
      final success = await LinkHandler.handle(
        context,
        url,
        (tab) {
          debugPrint('UrlService: Opening tab: ${tab.title}');
          context.read<TabsBloc>().add(AddTab(tab));
          context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
        },
      );
      
      if (success) {
        debugPrint('UrlService: URL processed successfully');
      } else {
        debugPrint('UrlService: URL processing returned false');
      }
    } catch (e, stackTrace) {
      debugPrint('UrlService: Error processing URL: $e');
      debugPrint('UrlService: Stack trace: $stackTrace');
    }
  }

  /// הבאת החלון לחזית
  static Future<void> bringToFront() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      
      await windowManager.show();
      await windowManager.focus();
      
      debugPrint('UrlService: Brought window to front');
    } catch (e) {
      debugPrint('UrlService: Error bringing window to front: $e');
    }
  }
}