import 'dart:convert';
import 'dart:typed_data';

const installedPdfPageSizes = [
  (width: 240, height: 320),
  (width: 320, height: 240),
  (width: 200, height: 400),
  (width: 400, height: 200),
];
const installedPdfQuery = 'bundleruntime';

String installedPdfPageToken(int pageNumber) => 'bundlepage$pageNumber';

/// מסמך קבוע עם טקסט ומלבן שחור; ללא גופני מערכת, תאריכים או רשת.
Uint8List createInstalledPdfFixture() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count ${installedPdfPageSizes.length} /Kids [ '
        '${List.generate(installedPdfPageSizes.length, (i) => '${4 + i * 2} 0 R').join(' ')} ] >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (var i = 0; i < installedPdfPageSizes.length; i++) {
    final size = installedPdfPageSizes[i];
    final content =
        '1 g 0 0 ${size.width} ${size.height} re f 0 g\n'
        'BT /F1 12 Tf 20 ${size.height - 30} Td '
        '($installedPdfQuery ${installedPdfPageToken(i + 1)}) Tj ET\n'
        '0 g 20 20 60 60 re f\n';
    objects.addAll([
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${size.width} ${size.height}] '
          '/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>',
      '<< /Length ${ascii.encode(content).length} >>\nstream\n${content}endstream',
    ]);
  }
  final bytes = BytesBuilder(copy: false)..add(ascii.encode('%PDF-1.7\n'));
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(bytes.length);
    bytes.add(ascii.encode('${i + 1} 0 obj\n${objects[i]}\nendobj\n'));
  }
  final xref = bytes.length;
  bytes.add(ascii.encode('xref\n0 ${offsets.length}\n0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    bytes.add(ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'));
  }
  bytes.add(
    ascii.encode(
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
    ),
  );
  return bytes.takeBytes();
}
