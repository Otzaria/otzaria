import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:win32/win32.dart';

/// מצב הפוקוס והמקלדת לדיווח (#3759). טופס הדיווח לוקח את הפוקוס, ולכן נשמרים
/// גם המעברים שקדמו לו. אין כאן תוכן מוקלד, רק איפה הפוקוס היה ואילו מקשים לחוצים.
class InputFocusDiagnostics {
  InputFocusDiagnostics._();

  static final InputFocusDiagnostics instance = InputFocusDiagnostics._();

  static const int maxHistory = 20;

  final Queue<Map<String, Object?>> _history = Queue();
  FocusManager? _focusManager;
  Stopwatch? _clock;

  /// מתחיל לרשום מעברי פוקוס. פעם אחת לתהליך.
  void install({FocusManager? focusManager}) {
    if (_focusManager != null) return;
    _focusManager = focusManager ?? FocusManager.instance;
    _clock = Stopwatch()..start();
    _focusManager!.addListener(_onFocusChanged);
  }

  @visibleForTesting
  void resetForTesting() {
    _focusManager?.removeListener(_onFocusChanged);
    _focusManager = null;
    _clock = null;
    _history.clear();
  }

  void _onFocusChanged() {
    final entry = describeFocus(_focusManager?.primaryFocus);
    final last = _history.isEmpty ? null : _history.last;
    if (last != null && jsonEncode(_withoutTime(last)) == jsonEncode(entry)) {
      return;
    }
    _history.add({'atMs': _clock!.elapsedMilliseconds, ...entry});
    while (_history.length > maxHistory) {
      _history.removeFirst();
    }
  }

  static Map<String, Object?> _withoutTime(Map<String, Object?> entry) =>
      Map.of(entry)..remove('atMs');

  /// המקטע לדיווח. `msAgo` בכל מעבר — כמה זמן לפני איסוף הדוח.
  Map<String, dynamic> collect() {
    final now = _clock?.elapsedMilliseconds;
    final keyboard = HardwareKeyboard.instance;
    return {
      'primaryFocus': describeFocus(FocusManager.instance.primaryFocus),
      'pressedKeys': [
        for (final key in keyboard.logicalKeysPressed) key.keyLabel,
      ],
      'lockModes': [for (final mode in keyboard.lockModesEnabled) mode.name],
      if (now != null)
        'recentFocus': [
          for (final entry in _history)
            {
              'msAgo': now - (entry['atMs']! as int),
              ..._withoutTime(entry),
            },
        ],
      if (!kIsWeb && Platform.isWindows) 'native': _nativeWin32(),
    };
  }

  /// סוג היעד, המסלול, הווידג'טים הקרובים אליו, ו-`screen`: הווידג'ט העליון
  /// בתוך המסלול (הדיאלוג או המסך), כי הקרובים הם לרוב רכיבי Material.
  @visibleForTesting
  static Map<String, Object?> describeFocus(FocusNode? node) {
    final context = node?.context;
    if (node == null || context == null) return {'kind': 'none'};
    final route = ModalRoute.of(context);
    final owners = <String>[];
    String? screen;
    var depth = 0;
    context.visitAncestorElements((element) {
      final name = element.widget.runtimeType.toString();
      if (name.startsWith('_ModalScope')) return false;
      if (!_isPlumbing(name)) {
        screen = name;
        if (owners.length < 5 && (owners.isEmpty || owners.last != name)) {
          owners.add(name);
        }
      }
      return ++depth < 400;
    });
    return {
      'kind': context.findAncestorWidgetOfExactType<EditableText>() != null
          ? 'text'
          : route is PopupRoute
          ? 'popup'
          : 'other',
      'route': ?route?.runtimeType.toString(),
      'screen': ?screen,
      'owners': owners,
      if (node is FocusScopeNode) 'scope': true,
    };
  }

  static final RegExp _plumbingName = RegExp(
    r'^(_|Raw|Default|Unmanaged|Undo|Inherited)|<|(Scope|Region|Detector|Boundary|Listener|Builder|Notification|Transition|Provider)$',
  );

  static bool _isPlumbing(String name) =>
      _plumbingName.hasMatch(name) || _genericWidgets.contains(name);

  static const Set<String> _genericWidgets = {
    'Focus',
    'FocusTraversalGroup',
    'Actions',
    'Shortcuts',
    'Semantics',
    'KeyedSubtree',
    'Padding',
    'SizedBox',
    'ConstrainedBox',
    'Container',
    'DecoratedBox',
    'Align',
    'Center',
    'Expanded',
    'Flexible',
    'Row',
    'Column',
    'Stack',
    'Material',
    'EditableText',
    'CompositedTransformTarget',
    'IgnorePointer',
    'AbsorbPointer',
    'Directionality',
    'IconTheme',
    'Theme',
    'MediaQuery',
    // עטיפות שכל מסלול מוסיף מעל התוכן שלו.
    'Offstage',
    'PageStorage',
    'PrimaryScrollController',
    'ColoredBox',
    'FractionalTranslation',
    'SafeArea',
    'DisplayFeatureSubScreen',
  };

  /// החלון שמחזיק את מקלדת המערכת: WebView של תוסף יחזיק אותה בלי ש-Flutter ידע.
  static Map<String, Object?> _nativeWin32() {
    final focused = GetFocus();
    final foreground = GetForegroundWindow();
    return {
      'focusClass': focused.isNull ? null : _className(focused),
      'foregroundIsApp':
          !foreground.isNull && _processOf(foreground) == GetCurrentProcessId(),
      'keyboardLayout':
          '0x${GetKeyboardLayout(0).address.toRadixString(16).padLeft(8, '0')}',
    };
  }

  static String _className(HWND hwnd) => using((arena) {
    final buffer = arena<Uint16>(256).cast<Utf16>();
    final length = GetClassName(hwnd, PWSTR(buffer), 256).value;
    return length <= 0 ? '' : buffer.toDartString(length: length);
  });

  static int _processOf(HWND hwnd) => using((arena) {
    final pid = arena<Uint32>();
    GetWindowThreadProcessId(hwnd, pid);
    return pid.value;
  });
}
