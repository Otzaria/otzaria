import 'dart:developer';
import 'dart:isolate';

/// מוסר לבקר המאומת את שירות ה־VM של מופע הסימולטור הנוכחי.
Future<Map<String, Object?>> iosSimulatorVmService() async {
  final info = await Service.controlWebServer(
    enable: true,
  ).timeout(const Duration(seconds: 10));
  final uri = info.serverUri;
  final isolate = Service.getIsolateId(Isolate.current);
  if (uri == null || isolate == null) {
    throw StateError('Simulator VM service or UI isolate is unavailable');
  }
  return {'vmServiceUri': uri.toString(), 'vmServiceIsolate': isolate};
}
