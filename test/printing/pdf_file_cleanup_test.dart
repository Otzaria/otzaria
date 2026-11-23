import 'package:otzaria/printing/pdf_export_cancellation.dart';
import 'package:otzaria/printing/pdf_file_cleanup.dart';
import 'package:test/test.dart';

void main() {
  test('cleans up a successful action and preserves its result', () async {
    var cleaned = false;
    expect(await withPdfFileCleanup(() => 42, () => cleaned = true), 42);
    expect(cleaned, isTrue);
  });

  test('reports cleanup failure after a successful action', () async {
    final error = StateError('close failed');
    await expectLater(
      withPdfFileCleanup(() => 42, () => throw error),
      throwsA(same(error)),
    );
  });

  test(
    'preserves the original write error and stack when cleanup also fails',
    () async {
      final primary = StateError('write failed');
      final stack = StackTrace.fromString('original write location');
      try {
        await withPdfFileCleanup<void>(
          () => Error.throwWithStackTrace(primary, stack),
          () => throw StateError('delete failed'),
        );
        fail('Expected the write error.');
      } catch (error, actualStack) {
        expect(error, same(primary));
        expect(actualStack.toString(), stack.toString());
      }
    },
  );

  test('cancellation stays identifiable after cleanup failure', () async {
    await expectLater(
      withPdfFileCleanup(
        () => throw const PdfExportCancelledException(),
        () => throw StateError('delete failed'),
      ),
      throwsA(isA<PdfExportCancelledException>()),
    );
  });

  test('synchronous patch cleanup also preserves the primary failure', () {
    final error = StateError('patch write failed');
    expect(
      () => withPdfFileCleanupSync(
        () => throw error,
        () => throw StateError('seek failed'),
      ),
      throwsA(same(error)),
    );
  });
}
