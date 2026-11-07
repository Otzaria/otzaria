import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/app_report_image_sources.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:super_clipboard/super_clipboard.dart';

class _Progress implements ReadProgress {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _File extends DataReaderFile {
  _File(this.bytes, {this.reportSize = true});
  final Uint8List bytes;
  final bool reportSize;
  @override
  String get fileName => 'copied.gif';
  @override
  int? get fileSize => reportSize ? bytes.length : null;
  @override
  Stream<Uint8List> getStream() async* {
    yield Uint8List.sublistView(bytes, 0, bytes.length ~/ 2);
    yield Uint8List.sublistView(bytes, bytes.length ~/ 2);
  }

  @override
  void close() {}
  @override
  Future<Uint8List> readAll() => throw StateError('must use bounded reads');
}

class _Item extends ClipboardDataReader {
  _Item({
    this.text,
    this.advertiseText = false,
    this.files = const {},
    this.reportSize = true,
  });
  final String? text;
  final bool advertiseText;
  final Map<FileFormat, Uint8List> files;
  final bool reportSize;
  final List<FileFormat?> reads = [];

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) => [
    for (final format in allFormats)
      if (files.containsKey(format) ||
          (advertiseText && format == Formats.plainText))
        format,
  ];

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async =>
      text as T?;

  @override
  ReadProgress? getFile(
    FileFormat? format,
    AsyncValueChanged<DataReaderFile> onFile, {
    ValueChanged<Object>? onError,
    bool allowVirtualFiles = true,
    bool synthesizeFilesFromURIs = true,
  }) {
    reads.add(format);
    final bytes = files[format];
    if (bytes == null) return null;
    scheduleMicrotask(() => onFile(_File(bytes, reportSize: reportSize)));
    return _Progress();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'text format with no text does not hide a screenshot in a text field',
    () async {
      for (final text in [null, '']) {
        final item = _Item(
          text: text,
          advertiseText: true,
          files: {Formats.png: Uint8List(4)},
        );
        final source = AppReportImageSources(
          clipboardReader: () async => ClipboardReader([item]),
        );
        final images = await source.readClipboard(skipIfText: true);
        expect(images, hasLength(1));
        expect(images.single.mimeType, 'image/png');
      }
    },
  );

  test(
    'real text has precedence in a field, explicit image paste can override it',
    () async {
      final item = _Item(
        text: 'טקסט רגיל',
        advertiseText: true,
        files: {Formats.png: Uint8List(4)},
      );
      final source = AppReportImageSources(
        clipboardReader: () async => ClipboardReader([item]),
      );
      expect(await source.readClipboard(skipIfText: true), isEmpty);
      expect(item.reads, isEmpty);
      expect(await source.readClipboard(), hasLength(1));
    },
  );

  test(
    'GIF bytes are preserved when a PNG alternative is also available',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'packages/otzaria_report_contract/test/fixtures/app_report_schema2.json',
                ).readAsStringSync(),
              )
              as Map;
      final gif = base64Decode(
        ((fixture['stored'] as Map)['images'] as List).first['data'] as String,
      );
      final item = _Item(files: {Formats.png: Uint8List(4), Formats.gif: gif});
      final source = AppReportImageSources(
        clipboardReader: () async => ClipboardReader([item]),
      );
      final result = (await source.readClipboard()).single;
      expect(result.mimeType, 'image/gif');
      expect(result.bytes, gif);
      expect(item.reads, [Formats.gif]);
    },
  );

  test(
    'clipboard reads enforce the byte boundary with or without a size hint',
    () async {
      for (final reportSize in [true, false]) {
        for (final size in [
          AppReportImage.maxBytes,
          AppReportImage.maxBytes + 1,
        ]) {
          final item = _Item(
            files: {Formats.png: Uint8List(size)},
            reportSize: reportSize,
          );
          final source = AppReportImageSources(
            clipboardReader: () async => ClipboardReader([item]),
          );
          final incoming = await source.readClipboard();
          final result = mergeAppReportImages([], incoming);
          expect(result.images.length, size == AppReportImage.maxBytes ? 1 : 0);
          expect(
            result.rejection,
            size == AppReportImage.maxBytes
                ? null
                : AppReportImageRejection.tooLarge,
          );
        }
      }
    },
  );
}
