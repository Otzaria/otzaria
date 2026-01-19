// This file has been moved to lib/links/ui/sharing_links.dart
// Import the new module instead:
// import 'package:otzaria/links/links.dart';

import 'package:otzaria/links/ui/sharing_links.dart';

/// Legacy wrapper for SharingUtils - use SharingLinks instead
/// 
/// This class is deprecated and will be removed in a future version.
/// Please use the new links module: import 'package:otzaria/links/links.dart';
@Deprecated('Use SharingLinks from the links module instead')
class SharingUtils {
  
  @Deprecated('Use SharingLinks.getCurrentSectionIndex instead')
  static int getCurrentSectionIndex(tab, positionsListener, state) {
    return SharingLinks.getCurrentSectionIndex(tab, positionsListener, state);
  }

  @Deprecated('Use SharingLinks.generateBookLink instead')
  static String generateBookLink(tab) {
    return SharingLinks.generateBookLink(tab);
  }

  @Deprecated('Use SharingLinks.generateSectionLink instead')
  static String generateSectionLink(tab) {
    return SharingLinks.generateSectionLink(tab);
  }

  @Deprecated('Use SharingLinks.generateHighlightedTextLink instead')
  static String generateHighlightedTextLink(tab, {String? selectedText}) {
    return SharingLinks.generateHighlightedTextLink(tab, selectedText: selectedText);
  }

  @Deprecated('Use SharingLinks.copyLinkToClipboard instead')
  static Future<void> copyLinkToClipboard(link, successMessage, showSnackBar, showErrorSnackBar) async {
    return SharingLinks.copyLinkToClipboard(link, successMessage, showSnackBar, showErrorSnackBar);
  }

  @Deprecated('Use SharingLinks.shareBookLinkLegacy instead')
  static Future<void> shareBookLink(tab, showSnackBar, showErrorSnackBar) async {
    return SharingLinks.shareBookLinkLegacy(tab, showSnackBar, showErrorSnackBar);
  }

  @Deprecated('Use SharingLinks.shareSectionLink instead')
  static Future<void> shareSectionLink(tab, showSnackBar, showErrorSnackBar) async {
    return SharingLinks.shareSectionLink(tab, showSnackBar, showErrorSnackBar);
  }

  @Deprecated('Use SharingLinks.shareHighlightedTextLink instead')
  static Future<void> shareHighlightedTextLink(tab, showSnackBar, showErrorSnackBar, {String? selectedText}) async {
    return SharingLinks.shareHighlightedTextLink(tab, showSnackBar, showErrorSnackBar, selectedText: selectedText);
  }
}