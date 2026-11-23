import 'dart:convert';
import 'dart:io';

import 'src/pdf_reader_case.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError(
      'Usage: prepare_pdf_case.dart <case.json> <snapshot.json>',
    );
  }
  await snapshotPerfPdfCase(File(arguments[0]), File(arguments[1]));
}

Future<void> snapshotPerfPdfCase(File input, File output) async {
  final pdfCase = await PerfPdfCase.load(input.path);
  await pdfCase.verifyExternalSource();
  await output.create(exclusive: true);
  await output.writeAsString('${jsonEncode(pdfCase.toJson())}\n', flush: true);
}
