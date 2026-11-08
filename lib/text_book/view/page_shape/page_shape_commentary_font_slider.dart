import 'package:flutter/material.dart';
import 'package:otzaria/settings/widgets/settings_slider_tile.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// מחוון "גודל גופן מפרשים" של צורת הדף, בהגדרה של צורת הדף
/// ([PageShapeSettingsManager]) ולא בהגדרה הכללית. אחד לחלונית צורת הדף
/// ולחלונית הכללית (#3244): שתיהן מאזינות לאותה שמירה, ולכן שינוי באחת מופיע
/// בשנייה, גם כששתיהן פתוחות.
///
/// הערך נשמר בסוף הגרירה: כל שמירה בונה מחדש את טורי המפרשים בדף.
class PageShapeCommentaryFontSizeSlider extends StatefulWidget {
  const PageShapeCommentaryFontSizeSlider({
    super.key,
    required this.title,
    this.onSaved,
  });

  final String title;

  /// אחרי השמירה, למשל רענון ההגדרות של חלונית צורת הדף.
  final VoidCallback? onSaved;

  @override
  State<PageShapeCommentaryFontSizeSlider> createState() =>
      _PageShapeCommentaryFontSizeSliderState();
}

class _PageShapeCommentaryFontSizeSliderState
    extends State<PageShapeCommentaryFontSizeSlider> {
  late double _value = _saved;

  static double get _saved =>
      PageShapeSettingsManager.getCommentaryFontSize().clamp(
        PageShapeSettingsManager.minCommentaryFontSize,
        PageShapeSettingsManager.maxCommentaryFontSize,
      );

  @override
  void initState() {
    super.initState();
    PageShapeSettingsManager.commentaryFontSizeChanges.addListener(_reload);
  }

  @override
  void dispose() {
    PageShapeSettingsManager.commentaryFontSizeChanges.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _value = _saved);
  }

  Future<void> _save(double value) async {
    await PageShapeSettingsManager.saveCommentaryFontSize(value);
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    const min = PageShapeSettingsManager.minCommentaryFontSize;
    const max = PageShapeSettingsManager.maxCommentaryFontSize;
    return SettingsSliderTile(
      icon: OtzariaIcons.beit_near_alef_24_filled,
      title: widget.title,
      valueLabel: _value.toStringAsFixed(0),
      value: _value,
      min: min,
      max: max,
      divisions: (max - min).toInt(),
      onChanged: (value) => setState(() => _value = value),
      onChangeEnd: _save,
    );
  }
}
