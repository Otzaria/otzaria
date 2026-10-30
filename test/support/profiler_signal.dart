import 'dart:ffi';
import 'dart:io';

/// ה-profiler של `flutter test` שולח SIGPROF כל מילישנייה, וב-Linux האות קוטע את
/// השינה של SQLite: busy_timeout נגמר אחרי ~60ms. ב-release אין profiler.
void ignoreProfilerSignalOnLinux() {
  if (!Platform.isLinux) return;
  const sigprof = 27;
  final sigIgn = Pointer<Void>.fromAddress(1);
  DynamicLibrary.process().lookupFunction<
    Pointer<Void> Function(Int32, Pointer<Void>),
    Pointer<Void> Function(int, Pointer<Void>)
  >('signal')(sigprof, sigIgn);
}
