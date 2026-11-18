import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/text_encoding_models.dart';

void main() {
  test('encoding labels and legacy classification are stable', () {
    expect(TextEncoding.utf8.label, 'UTF-8');
    expect(TextEncoding.windows1255.label, 'Windows-1255');
    expect(TextEncoding.iso88598.isLegacyHebrew, isTrue);
    expect(TextEncoding.cp862.isLegacyHebrew, isTrue);
    expect(TextEncoding.utf16LE.isLegacyHebrew, isFalse);
    expect(TextEncoding.utf32BE.isUtf32, isTrue);
    expect(TextEncoding.utf16BE.isUtf32, isFalse);
  });

  test('detection exposes confidence and BOM metadata', () {
    const detection = TextEncodingDetection(
      encoding: TextEncoding.utf8,
      confidence: 0.59,
      reason: 'probe',
      hadBom: true,
      bomLength: 3,
      validPrefixLength: 12,
      candidateScores: {TextEncoding.utf8: 0.59},
    );

    expect(detection.lowConfidence, isTrue);
    expect(detection.hadBom, isTrue);
    expect(detection.bomLength, 3);
    expect(detection.validPrefixLength, 12);
    expect(detection.candidateScores[TextEncoding.utf8], 0.59);
  });

  test('decoding result preserves forced encoding and candidate scores', () {
    const result = TextDecodingResult(
      text: 'שלום',
      encoding: TextEncoding.windows1255,
      confidence: 0.9,
      hadBom: false,
      detectionReason: 'legacy',
      encodingWasForced: true,
      candidateScores: {TextEncoding.windows1255: 0.9},
    );

    expect(result.lowConfidence, isFalse);
    expect(result.encodingWasForced, isTrue);
    expect(result.text, 'שלום');
    expect(result.candidateScores[TextEncoding.windows1255], 0.9);
  });

  test('decoded candidate retains evidence fields', () {
    const candidate = DecodedCandidate(
      encoding: TextEncoding.utf8,
      score: 0.8,
      plausibility: 0.95,
      distinctiveBytes: 3,
      highBytes: 10,
      sampleLength: 128,
    );

    expect(candidate.score, 0.8);
    expect(candidate.plausibility, 0.95);
    expect(candidate.distinctiveBytes, 3);
    expect(candidate.highBytes, 10);
    expect(candidate.sampleLength, 128);
  });
}
