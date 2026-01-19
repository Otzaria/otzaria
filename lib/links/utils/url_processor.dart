import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/links/core/link_handler.dart';

/// Utility class for processing URLs when app is launched or receives URLs
class UrlProcessor {
  
  /// Handle initial URL when app is launched with otzaria:// scheme
  static void handleInitialUrl(
    BuildContext context,
    String url,
    VoidCallback? onProcessingComplete,
  ) {
    debugPrint('UrlProcessor: Received initial URL: $url');
    
    // Wait for the app to be fully initialized before handling the URL
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        debugPrint('UrlProcessor: Context not mounted, skipping URL handling');
        return;
      }
      
      // Wait for library to be loaded using state-driven approach
      final libraryBloc = context.read<LibraryBloc>();
      
      // If library is already loaded, handle URL immediately
      if (libraryBloc.state.library != null && !libraryBloc.state.isLoading) {
        debugPrint('UrlProcessor: Library already loaded, handling URL immediately');
        await processUrl(context, url);
        onProcessingComplete?.call();
        return;
      }
      
      // Otherwise, listen for library to load
      debugPrint('UrlProcessor: Waiting for library to load...');
      
      try {
        await libraryBloc.stream.firstWhere(
          (state) => state.library != null && !state.isLoading,
        );
        
        debugPrint('UrlProcessor: Library loaded, handling URL now');
        if (context.mounted) {
          await processUrl(context, url);
          onProcessingComplete?.call();
        } else {
          debugPrint('UrlProcessor: Context unmounted after library load, skipping URL processing');
        }
      } catch (e) {
        debugPrint('UrlProcessor: Error waiting for library: $e');
      }
    });
  }
  
  /// Process the URL after library is loaded
  static Future<void> processUrl(BuildContext context, String url) async {
    debugPrint('UrlProcessor: Starting URL handling for: $url');
    
    try {
      // Handle the URL using the existing link handler
      final success = await LinkHandler.handleLink(
        context,
        url,
        (tab) {
          debugPrint('UrlProcessor: Opening tab: ${tab.title}');
          // Open the tab using the TabsBloc
          context.read<TabsBloc>().add(AddTab(tab));
          // Navigate to reading screen
          context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
        },
      );
      
      if (success) {
        debugPrint('UrlProcessor: URL handled successfully');
      } else {
        debugPrint('UrlProcessor: URL handling returned false');
      }
    } catch (e, stackTrace) {
      debugPrint('UrlProcessor: Error handling URL: $e');
      debugPrint('UrlProcessor: Stack trace: $stackTrace');
    }
  }

  /// Bring the window to front and focus it
  static Future<void> bringWindowToFront() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    try {
      // Show the window if it's minimized
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      
      // Bring to front and focus
      await windowManager.show();
      await windowManager.focus();
      
      debugPrint('UrlProcessor: Brought window to front');
    } catch (e) {
      debugPrint('UrlProcessor: Error bringing window to front: $e');
    }
  }
}