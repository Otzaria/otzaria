import 'package:flutter/widgets.dart';

/// בודקת האם [focusNode] נמצא בתוך שדה קלט טקסטואלי.
///
/// מכסה שדות Flutter רגילים המבוססים על [EditableText], וגם עורכי Quill שאינם
/// תמיד נחשפים כ-[EditableText] בעץ הווידג'טים.
bool isTextInputFocusNode(FocusNode? focusNode) {
  final focusContext = focusNode?.context;
  if (focusContext == null) {
    return false;
  }
  return isTextInputContext(focusContext);
}

/// בודקת האם [context] שייך לשדה קלט טקסטואלי או נמצא תחת אחד כזה.
bool isTextInputContext(BuildContext context) {
  if (isTextInputWidget(context.widget)) {
    return true;
  }

  var found = false;
  context.visitAncestorElements((element) {
    if (isTextInputWidget(element.widget)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// בודקת האם [widget] הוא שדה קלט טקסטואלי או עורך טקסט עשיר מוכר.
bool isTextInputWidget(Widget widget) {
  if (widget is EditableText) {
    return true;
  }

  final name = widget.runtimeType.toString();
  return name.contains('QuillRawEditor') ||
      name.contains('RawEditor') ||
      name.contains('QuillEditor');
}
