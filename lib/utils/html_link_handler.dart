import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/links/core/link_handler.dart';

/// מחלקה לטיפול בקישורי HTML בתוך הטקסט
/// 
/// הערה: מחלקה זו נשארת לתאימות לאחור.
/// לשימוש חדש, השתמש ב-LinkHandler מהמודול links/
class HtmlLinkHandler {

  /// מטפל בלחיצה על קישור HTML
  /// 
  /// הפונקציה מעבירה את הטיפול ל-LinkHandler החדש
  static Future<bool> handleLink(
    BuildContext context,
    String url,
    Function(OpenedTab) openBookCallback,
  ) async {
    return await LinkHandler.handleLink(context, url, openBookCallback);
  }
}