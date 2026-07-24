import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// בדיקה זולה אם כותרת ספר היא רש"י — בבלי מכונה "רש"י על <מסכת>" וחומש
/// "רש"י על <ספר>", אך יש לכסות גם "רש"י" חשוף למקרה שהמסד יכיל כזה. משמש
/// כשער-קדם לפני גישה למפת הלעזים, כדי שטורי מפרש אחרים לא ישלמו דבר.
bool isRashiTitle(String title) {
  return title == 'רש"י' ||
      title.startsWith('רש"י על') ||
      title.startsWith('רש"י ');
}

/// תת-בלוק המציג את ערכי "אוצר לעזי רש"י" המקושרים לשורת הרש"י הנוכחית,
/// מתחת לטקסט הפירוש. כל ערך: שם הלעז מודגש + הפירוש העברי באותה שורה.
/// נעדר בשקט אם אין לעז לשורה או אם הספר חסר במסד.
class LaazCommentarySubBlock extends StatefulWidget {
  /// חיווט מבוסס-Link: גוזר את כותרת הרש"י והשורה מתוך יעד הקישור.
  const LaazCommentarySubBlock({
    super.key,
    required Link this.link,
    this.repository,
  }) : rashiBookTitle = null,
       rashiLineIndex = null,
       baseFontSize = null;

  /// חיווט ישיר לפי כותרת ספר רש"י ומספר שורה (1-based), ללא Link.
  /// לשימוש בצורת-הדף, שם טור המפרש מרנדר שורה שלמה ואין אובייקט Link.
  /// [baseFontSize] — גודל גופן טור המפרש; הלעז מוקטן ממנו כדי להתאים לטור
  /// הצר, במקום להיגזר מ-commentatorsFontSize הכללי (שאינו חל על צורת-הדף).
  const LaazCommentarySubBlock.forLine({
    super.key,
    required String this.rashiBookTitle,
    required int this.rashiLineIndex,
    this.baseFontSize,
    this.repository,
  }) : link = null;

  final Link? link;

  /// גודל גופן הבסיס לגזירת גודל הלעז (מסלול [LaazCommentarySubBlock.forLine]).
  final double? baseFontSize;

  /// כותרת ספר הרש"י ומספר השורה (1-based) — במסלול [LaazCommentarySubBlock.forLine].
  final String? rashiBookTitle;
  final int? rashiLineIndex;

  /// מוזרק בטסטים בלבד; בקוד האמיתי משתמשים ב-singleton.
  final DictionaryLookupRepository? repository;

  @override
  State<LaazCommentarySubBlock> createState() => _LaazCommentarySubBlockState();
}

class _LaazCommentarySubBlockState extends State<LaazCommentarySubBlock> {
  DictionaryLookupRepository get _repository =>
      widget.repository ?? DictionaryLookupRepository.instance;

  /// כותרת ספר הרש"י לשני המסלולים (מתוך ה-Link או מהפרמטר הישיר).
  String get _rashiBookTitle {
    final link = widget.link;
    if (link != null) return utils.getTitleFromPath(link.path2);
    return widget.rashiBookTitle!;
  }

  /// מספר השורה (1-based) לשני המסלולים.
  int get _rashiLineIndex => widget.link?.index2 ?? widget.rashiLineIndex!;

  /// שער-כניסה זול (לפני כל גישה למפה): רק כותרת רש"י רלוונטית.
  /// במסלול ה-Link נדרש גם סוג קישור תלוי-טקסט.
  bool get _isRashiCommentaryLink {
    final link = widget.link;
    if (link != null && !LinkTypes.isDependentTextLink(link.connectionType)) {
      return false;
    }
    return isRashiTitle(_rashiBookTitle);
  }

  @override
  void initState() {
    super.initState();
    if (_isRashiCommentaryLink && !_repository.areLaazLinksLoaded) {
      unawaited(
        _repository
            .ensureLaazLinksLoaded()
            .then((_) {
              if (mounted) setState(() {});
            })
            .catchError((_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRashiCommentaryLink || !_repository.areLaazLinksLoaded) {
      return const SizedBox.shrink();
    }

    final entries = _repository.laazForRashiLine(
      rashiBookTitle: _rashiBookTitle,
      rashiLineIndex: _rashiLineIndex,
    );
    if (entries.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final baseSize =
            widget.baseFontSize ?? settingsState.commentatorsFontSize;
        final fontSize = baseSize * 0.85;
        final fontFamily = settingsState.commentatorsFontFamily;
        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: AppTokens.borderRadiusAll,
            border: Border(
              right: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in entries)
                _LaazEntryLine(
                  entry: entry,
                  fontSize: fontSize,
                  fontFamily: fontFamily,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// שורת ערך-לעז בודדת: שם הלעז מודגש ואחריו הפירוש העברי.
/// פירוש ריק => שם הלעז לבד (בלי שורת פירוש ריקה).
class _LaazEntryLine extends StatelessWidget {
  const _LaazEntryLine({
    required this.entry,
    required this.fontSize,
    required this.fontFamily,
  });

  final LaazDictionaryEntry entry;
  final double fontSize;
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = entry.laazHebrew.isNotEmpty ? entry.laazHebrew : entry.lemma;
    final baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.4,
      color: colorScheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: title,
              style: baseStyle.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (entry.meaning.isNotEmpty)
              TextSpan(text: ' ${entry.meaning}', style: baseStyle),
          ],
        ),
      ),
    );
  }
}
