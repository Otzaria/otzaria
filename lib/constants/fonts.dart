import 'package:flutter/material.dart';

/// רשימת הגופנים הזמינים באפליקציה
class AppFonts {
  AppFonts._();

  /// גופן ברירת מחדל לטקסט ראשי
  static const String defaultFont = 'FrankRuhlCLM';
  
  /// גופן ברירת מחדל למפרשים
  static const String defaultCommentatorsFont = 'NotoRashiHebrew';
  
  /// גופן לעריכת טקסט עם טעמים
  static const String editorFont = 'TaameyAshkenaz';

  /// רשימת כל הגופנים הזמינים לבחירה ב-UI
  /// הערה: Candara, roboto, Calibri, Arial הם גופני מערכת ולא קיימים בתיקיית fonts
  static const List<FontInfo> availableFonts = [
    FontInfo(value: 'TaameyDavidCLM', label: 'דוד'),
    FontInfo(value: 'FrankRuhlCLM', label: 'פרנק-רוהל'),
    FontInfo(value: 'TaameyAshkenaz', label: 'טעמי אשכנז'),
    FontInfo(value: 'KeterYG', label: 'כתר'),
    FontInfo(value: 'Shofar', label: 'שופר'),
    FontInfo(value: 'NotoSerifHebrew', label: 'נוטו'),
    FontInfo(value: 'Tinos', label: 'טינוס'),
    FontInfo(value: 'NotoRashiHebrew', label: 'רש"י'),
    FontInfo(value: 'Rubik', label: 'רוביק'),
    FontInfo(value: 'Candara', label: 'קנדרה'),
    FontInfo(value: 'roboto', label: 'רובוטו'),
    FontInfo(value: 'Calibri', label: 'קליברי'),
    FontInfo(value: 'Arial', label: 'אריאל'),
  ];

  /// מיפוי גופנים לנתיבי קבצים (לשימוש בהדפסה)
  /// הערה: רק גופנים עם קבצים בתיקיית fonts נתמכים בהדפסה
  static const Map<String, String> fontPaths = {
    'TaameyDavidCLM': 'fonts/TaameyDavidCLM-Medium.ttf',
    'FrankRuhlCLM': 'fonts/FrankRuehlCLM-Medium.ttf',
    'TaameyAshkenaz': 'fonts/TaameyAshkenaz-Medium.ttf',
    'KeterYG': 'fonts/KeterYG-Medium.ttf',
    'Shofar': 'fonts/ShofarRegular.ttf',
    'NotoSerifHebrew': 'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
    'Tinos': 'fonts/Tinos-Regular.ttf',
    'NotoRashiHebrew': 'fonts/NotoRashiHebrew-VariableFont_wght.ttf',
    'Rubik': 'fonts/Rubik-VariableFont_wght.ttf',
  };

  /// מיפוי גופנים לשמות בעברית (לשימוש בהדפסה)
  /// מחושב אוטומטית מ-availableFonts, רק עבור גופנים עם קבצים
  static Map<String, String> get fontLabels => {
        for (final font in availableFonts)
          if (fontPaths.containsKey(font.value)) font.value: font.label
      };

  /// יצירת רשימת DropdownMenuItem לבחירת גופן
  static List<DropdownMenuItem<String>> buildDropdownItems() {
    return availableFonts.map((font) {
      return DropdownMenuItem<String>(
        value: font.value,
        child: Text(
          font.label,
          style: TextStyle(fontFamily: font.value),
        ),
      );
    }).toList();
  }
}

/// מידע על גופן
class FontInfo {
  final String value;
  final String label;

  const FontInfo({required this.value, required this.label});
}
