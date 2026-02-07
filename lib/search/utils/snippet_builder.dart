import 'dart:math';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/search/utils/regex_patterns.dart';

class SnippetBuilder {
  /// פונקציה לחישוב כמה תווים יכולים להיכנס בשורה אחת
  static int calculateCharsPerLine(double availableWidth, TextStyle textStyle) {
    final textPainter = TextPainter(
      text: TextSpan(text: 'א' * 100, style: textStyle),
      textDirection: TextDirection.rtl,
    );
    textPainter.layout(maxWidth: availableWidth);

    final singleCharWidth = textPainter.width / 100;
    final charsPerLine = (availableWidth / singleCharWidth).floor();

    textPainter.dispose();
    return charsPerLine;
  }

  /// פונקציה חכמה ליצירת קטע טקסט עם הדגשות - מבטיחה שכל ההתאמות יופיעו!
  static List<InlineSpan> createSnippetSpans({
    required String fullHtml,
    required String query,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
    required double availableWidth,
    required Map<String, Map<String, bool>> searchOptions,
    required Map<int, List<String>> alternativeWords,
  }) {
    // 1. קבלת הטקסט הנקי מה-HTML
    final plainText =
        html_parser.parse(fullHtml).documentElement?.text.trim() ?? '';

    // 2. חילוץ מילות החיפוש כולל מילים חילופיות
    final originalWords = query
        .trim()
        .replaceAll(RegExp(r'[~"*\(\)]'), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    // הוספת מילים חילופיות ווריאציות כתיב מלא/חסר למילות החיפוש
    final searchTerms = <String>[];
    for (int i = 0; i < originalWords.length; i++) {
      final word = originalWords[i];
      final wordKey = '${word}_$i';

      // בדיקת אפשרויות החיפוש למילה הזו
      final wordOptions = searchOptions[wordKey] ?? {};
      final hasFullPartialSpelling = wordOptions['כתיב מלא/חסר'] == true;

      if (hasFullPartialSpelling) {
        // אם יש כתיב מלא/חסר, נוסיף את כל הווריאציות
        try {
          final variations =
              SearchRegexPatterns.generateFullPartialSpellingVariations(word);
          searchTerms.addAll(variations);
        } catch (e) {
          // אם יש בעיה, נוסיף לפחות את המילה המקורית
          searchTerms.add(word);
        }
      } else {
        // אם אין כתיב מלא/חסר, נוסיף את המילה המקורית
        searchTerms.add(word);
      }

      // הוספת מילים חילופיות אם יש
      final alternatives = alternativeWords[i];
      if (alternatives != null && alternatives.isNotEmpty) {
        if (hasFullPartialSpelling) {
          // אם יש כתיב מלא/חסר, נוסיף גם את הווריאציות של המילים החילופיות
          for (final alt in alternatives) {
            try {
              final altVariations =
                  SearchRegexPatterns.generateFullPartialSpellingVariations(
                      alt);
              searchTerms.addAll(altVariations);
            } catch (e) {
              searchTerms.add(alt);
            }
          }
        } else {
          searchTerms.addAll(alternatives);
        }
      }
    }

    if (searchTerms.isEmpty || plainText.isEmpty) {
      return [TextSpan(text: plainText, style: defaultStyle)];
    }

    // 3. מציאת כל ההתאמות של כל המילים בטקסט המקורי
    final List<Match> allMatches = [];
    for (final term in searchTerms) {
      final regex = RegExp(RegExp.escape(term), caseSensitive: false);
      allMatches.addAll(regex.allMatches(plainText));
    }

    if (allMatches.isEmpty) {
      return [
        TextSpan(
          text: plainText.substring(0, min(200, plainText.length)),
          style: defaultStyle,
        ),
      ];
    }

    // 4. מיון ההתאמות וקביעת הגבולות המוחלטים
    allMatches.sort((a, b) => a.start.compareTo(b.start));
    final int absoluteFirstMatch = allMatches.first.start;
    final int absoluteLastMatch = allMatches.last.end;
    final int totalMatchesSpan = absoluteLastMatch - absoluteFirstMatch;

    // 5. קביעת הקטע - עקרון ברזל: כל ההתאמות חייבות להיכלל!
    int snippetStart;
    int snippetEnd;

    // חישוב אורך הטקסט הנדרש לשלוש שורות בהתבסס על רוחב המסך בפועל
    final charsPerLine = calculateCharsPerLine(availableWidth, defaultStyle);
    final targetLength = (charsPerLine * 3).clamp(120, 400);

    // תמיד מתחילים מהגבולות המוחלטים של ההתאמות
    snippetStart = absoluteFirstMatch;
    snippetEnd = absoluteLastMatch;

    if (totalMatchesSpan < 50) {
      // אם המילים קרובות מאוד (כולל מילה אחת)
      // נוסיף הקשר מוגבל - מקסימום 60 תווים מכל צד
      const limitedPadding = 60;
      snippetStart =
          (absoluteFirstMatch - limitedPadding).clamp(0, plainText.length);
      snippetEnd =
          (absoluteLastMatch + limitedPadding).clamp(0, plainText.length);
    } else if (totalMatchesSpan < targetLength) {
      // אם ההתאמות קצרות מהיעד, נוסיף הקשר עד שנגיע ל-3 שורות
      int remainingSpace = targetLength - totalMatchesSpan;
      int paddingBefore = remainingSpace ~/ 2;
      int paddingAfter = remainingSpace - paddingBefore;

      snippetStart =
          (absoluteFirstMatch - paddingBefore).clamp(0, plainText.length);
      snippetEnd =
          (absoluteLastMatch + paddingAfter).clamp(0, plainText.length);
    } else {
      // אם ההתאמות ארוכות, נוסיף רק מעט הקשר
      const minPadding = 30;
      snippetStart =
          (absoluteFirstMatch - minPadding).clamp(0, plainText.length);
      snippetEnd = (absoluteLastMatch + minPadding).clamp(0, plainText.length);
    }

    // התאמה לגבולות מילים - אבל לא על חשבון ההתאמות!
    if (snippetStart > 0 && snippetStart < absoluteFirstMatch) {
      int? spaceIndex = plainText.lastIndexOf(' ', snippetStart);
      if (spaceIndex != -1 && spaceIndex >= snippetStart - 50) {
        snippetStart = spaceIndex + 1;
      } else {
        while (snippetStart > 0 && plainText[snippetStart - 1] != ' ') {
          snippetStart--;
        }
      }
    }

    if (snippetEnd < plainText.length && snippetEnd > absoluteLastMatch) {
      int? spaceIndex = plainText.indexOf(' ', snippetEnd);
      if (spaceIndex != -1 && spaceIndex <= snippetEnd + 50) {
        snippetEnd = spaceIndex;
      } else {
        while (snippetEnd < plainText.length && plainText[snippetEnd] != ' ') {
          snippetEnd++;
        }
      }
    }

    if (snippetStart > absoluteFirstMatch) {
      snippetStart = absoluteFirstMatch;
    }
    if (snippetEnd < absoluteLastMatch) {
      snippetEnd = absoluteLastMatch;
    }

    final snippetText = plainText.substring(snippetStart, snippetEnd);

    // 6. בדיקה נוספת - ספירת ההתאמות בקטע הסופי
    int finalMatchCount = 0;
    for (final term in searchTerms) {
      final regex = RegExp(RegExp.escape(term), caseSensitive: false);
      finalMatchCount += regex.allMatches(snippetText).length;
    }

    if (finalMatchCount < allMatches.length) {
      snippetStart = (absoluteFirstMatch - 100).clamp(0, plainText.length);
      snippetEnd = (absoluteLastMatch + 100).clamp(0, plainText.length);
      final expandedSnippet = plainText.substring(snippetStart, snippetEnd);

      int expandedMatchCount = 0;
      for (final term in searchTerms) {
        final regex = RegExp(RegExp.escape(term), caseSensitive: false);
        expandedMatchCount += regex.allMatches(expandedSnippet).length;
      }

      if (expandedMatchCount >= allMatches.length) {
        return _buildTextSpans(
            expandedSnippet, searchTerms, defaultStyle, highlightStyle);
      }
    }

    return _buildTextSpans(
        snippetText, searchTerms, defaultStyle, highlightStyle);
  }

  static List<InlineSpan> _buildTextSpans(
    String text,
    List<String> searchTerms,
    TextStyle defaultStyle,
    TextStyle highlightStyle,
  ) {
    final List<InlineSpan> spans = [];
    int currentPosition = 0;

    final highlightRegex = RegExp(
      searchTerms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );

    for (final match in highlightRegex.allMatches(text)) {
      if (match.start > currentPosition) {
        spans.add(TextSpan(
          text: text.substring(currentPosition, match.start),
          style: defaultStyle,
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: highlightStyle,
      ));
      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentPosition),
        style: defaultStyle,
      ));
    }

    return spans;
  }
}
