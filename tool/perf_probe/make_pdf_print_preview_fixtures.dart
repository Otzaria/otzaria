import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// Run separately so fixture construction is outside the probe's memory sample.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: dart run ${Platform.script} <output-directory>',
    );
  }
  final output = Directory(arguments.single);
  await output.create(recursive: true);
  for (final fixture in [
    (name: 'small', pages: 3, scanned: false, mixed: false),
    (name: 'mixed', pages: 600, scanned: false, mixed: true),
    (name: 'scanned', pages: 120, scanned: true, mixed: true),
  ]) {
    final file = File('${output.path}/${fixture.name}.pdf');
    final writer = _FixtureWriter(await file.open(mode: FileMode.write));
    final stride = fixture.scanned ? 3 : 2;
    final pageIds = List.generate(fixture.pages, (index) => 4 + index * stride);
    try {
      await writer.text('%PDF-1.7\n');
      await writer.object(1, '<< /Type /Catalog /Pages 2 0 R >>');
      await writer.object(
        2,
        '<< /Type /Pages /Count ${fixture.pages} /Kids '
        '[${pageIds.map((id) => '$id 0 R').join(' ')}] >>',
      );
      await writer.object(
        3,
        '<< /Type /Font /Subtype /Type1 '
        '/BaseFont /Helvetica >>',
      );
      for (var index = 0; index < fixture.pages; index++) {
        final size = !fixture.mixed
            ? (width: 595.28, height: 841.89)
            : switch (index % 4) {
                0 => (width: 595.28, height: 841.89),
                1 => (width: 419.53, height: 595.28),
                2 => (width: 841.89, height: 1190.55),
                _ => (width: 841.89, height: 595.28),
              };
        final pageId = pageIds[index];
        final imageResource = fixture.scanned
            ? '/XObject << /Im0 ${pageId + 2} 0 R >>'
            : '';
        await writer.object(
          pageId,
          '<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 ${size.width} ${size.height}] '
          '/Resources << /Font << /F1 3 0 R >> $imageResource >> '
          '/Contents ${pageId + 1} 0 R >>',
        );
        final content = StringBuffer(
          'BT /F1 14 Tf 18 ${size.height - 30} Td '
          '(PDF preview fixture - page ${index + 1}) Tj ET\n',
        );
        if (fixture.scanned) {
          content.write(
            'q ${size.width - 36} 0 0 ${size.height - 60} '
            '18 18 cm /Im0 Do Q\n',
          );
        } else {
          for (var line = 0; line < 18; line++) {
            content.write(
              'BT /F1 10 Tf 18 ${size.height - 55 - line * 18} Td '
              '(Sample ${line + 1}: 0123456789 ABCDEFG) Tj ET\n',
            );
          }
        }
        await writer.stream(pageId + 1, '', ascii.encode(content.toString()));
        if (fixture.scanned) {
          const width = 512;
          const height = 768;
          final random = Random(index + 1);
          final pixels = Uint8List(width * height);
          for (var pixel = 0; pixel < pixels.length; pixel++) {
            pixels[pixel] = random.nextInt(256);
          }
          await writer.stream(
            pageId + 2,
            '/Type /XObject /Subtype /Image /Width $width /Height $height '
            '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode',
            zlib.encode(pixels),
          );
        }
      }
      await writer.finish();
    } finally {
      await writer.file.close();
    }
    stdout.writeln(
      '${file.path}: ${file.lengthSync()} bytes, '
      '${fixture.pages} pages',
    );
  }
}

class _FixtureWriter {
  _FixtureWriter(this.file);
  final RandomAccessFile file;
  final offsets = <int>[0];

  Future<void> text(String value) async {
    await file.writeString(value, encoding: ascii);
  }

  Future<void> object(int id, String value) async {
    await _begin(id);
    await text('$value\nendobj\n');
  }

  Future<void> stream(int id, String dictionary, List<int> bytes) async {
    await _begin(id);
    await text('<< $dictionary /Length ${bytes.length} >>\nstream\n');
    await file.writeFrom(bytes);
    await text('\nendstream\nendobj\n');
  }

  Future<void> _begin(int id) async {
    if (id != offsets.length) throw StateError('Nonsequential PDF object');
    offsets.add(await file.position());
    await text('$id 0 obj\n');
  }

  Future<void> finish() async {
    final start = await file.position();
    await text('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      await text('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    await text(
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\n'
      'startxref\n$start\n%%EOF\n',
    );
    await file.flush();
  }
}
