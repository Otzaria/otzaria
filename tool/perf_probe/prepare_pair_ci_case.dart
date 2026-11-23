import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'make_pdf_print_preview_fixtures.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError(
      'Usage: prepare_pair_ci_case.dart <new-directory> <pages>',
    );
  }
  final pages = int.parse(arguments[1]);
  if (pages < 1 || pages > 10000) throw ArgumentError.value(pages, 'pages');
  final directory = Directory(arguments[0]).absolute;
  if (await FileSystemEntity.type(directory.path) !=
      FileSystemEntityType.notFound) {
    throw StateError('The CI corpus directory must not already exist.');
  }
  await directory.create(recursive: true);
  final pdf = File('${directory.path}/corpus.pdf');
  await writePdfProbeFixture(pdf, pageCount: pages, mixed: true);
  final digest = await sha256.bind(pdf.openRead()).first;
  await File('${directory.path}/case.json').writeAsString(
    '${jsonEncode({
      'schemaVersion': 1,
      'source': {
        'kind': 'external',
        'path': 'corpus.pdf',
        'sha256': digest.toString(),
        'pageCount': pages,
      },
    })}\n',
    flush: true,
  );
}
