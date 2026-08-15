import 'package:equatable/equatable.dart';

class AnkiNativeWindow extends Equatable {
  final String targetId;
  final String hwnd;
  final String title;
  final String kind;
  final bool active;
  final bool modal;
  final bool closable;

  const AnkiNativeWindow({
    required this.targetId,
    required this.hwnd,
    required this.title,
    required this.kind,
    required this.active,
    required this.modal,
    required this.closable,
  });

  factory AnkiNativeWindow.fromJson(Map<String, dynamic> json) {
    final targetId = json['targetId'];
    final hwnd = json['hwnd'];
    if (targetId is! String || targetId.isEmpty) {
      throw const FormatException('targetId חסר בתשובת Anki');
    }
    if (hwnd is! String || !RegExp(r'^[0-9A-Fa-f]{1,16}$').hasMatch(hwnd)) {
      throw const FormatException('HWND אינו תקין בתשובת Anki');
    }
    return AnkiNativeWindow(
      targetId: targetId,
      hwnd: hwnd.toUpperCase(),
      title: json['title'] is String ? json['title'] as String : 'Anki',
      kind: json['kind'] is String ? json['kind'] as String : 'window',
      active: json['active'] == true,
      modal: json['modal'] == true,
      closable: json['closable'] == true,
    );
  }

  @override
  List<Object?> get props => [
    targetId,
    hwnd,
    title,
    kind,
    active,
    modal,
    closable,
  ];
}

class AnkiNativeSnapshot extends Equatable {
  final int processId;
  final String generation;
  final List<AnkiNativeWindow> windows;

  const AnkiNativeSnapshot({
    required this.processId,
    required this.generation,
    required this.windows,
  });

  @override
  List<Object?> get props => [processId, generation, windows];
}

class AnkiNativeBounds extends Equatable {
  final int x;
  final int y;
  final int width;
  final int height;

  const AnkiNativeBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, int> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  @override
  List<Object?> get props => [x, y, width, height];
}
