import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// ב-macOS הבורר בבעלות חלון נוצר בנפרד ועוקף את ה-instance המשותף.
void captureFileSaves(
  FilePickerPlatform picker,
  void Function(Uint8List bytes) onSave,
) {
  final previous = FilePickerPlatform.instance;
  FilePickerPlatform.instance = picker;
  addTearDown(() => FilePickerPlatform.instance = previous);
  if (!Platform.isMacOS) return;
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'save') {
      onSave(Uint8List.fromList((call.arguments['bytes'] as List).cast<int>()));
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}
