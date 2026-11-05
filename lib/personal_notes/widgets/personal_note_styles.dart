import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// ריווח משותף לעריכה ולתצוגה, בלי לשנות את העיצוב השמור בהערה.
quill.DefaultStyles personalNoteStyles(BuildContext context) {
  final styles = quill.DefaultStyles.getInstance(context);
  return styles.merge(
    quill.DefaultStyles(
      paragraph: styles.paragraph!.copyWith(
        style: styles.paragraph!.style.copyWith(height: 1.5),
      ),
      lists: styles.lists!.copyWith(
        style: styles.lists!.style.copyWith(height: 1.5),
      ),
      quote: styles.quote!.copyWith(
        style: styles.quote!.style.copyWith(height: 1.5),
      ),
      placeHolder: styles.placeHolder!.copyWith(
        style: styles.placeHolder!.style.copyWith(height: 1.5),
      ),
    ),
  );
}
