import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/process_duties.dart';

void main() {
  tearDown(() => ProcessDuties.debugOverride = null);

  test('ברירת המחדל היא בעל התהליך (החלון הראשי)', () {
    expect(ProcessDuties().isProcessOwner, isTrue);
    expect(ProcessDuties.current.isProcessOwner, isTrue);
  });

  testWidgets('of: המופע של החלון גובר על current, ובלעדיו — current', (
    tester,
  ) async {
    final view = ProcessDuties(
      isProcessOwner: () => false,
      hostsPluginBackground: false,
    );
    late ProcessDuties inView;
    late ProcessDuties outside;
    await tester.pumpWidget(
      Column(
        children: [
          RepositoryProvider<ProcessDuties>.value(
            value: view,
            child: Builder(
              builder: (context) {
                inView = ProcessDuties.of(context);
                return const SizedBox();
              },
            ),
          ),
          Builder(
            builder: (context) {
              outside = ProcessDuties.of(context);
              return const SizedBox();
            },
          ),
        ],
      ),
    );
    expect(inView, same(view));
    expect(inView.isProcessOwner, isFalse);
    expect(outside, same(ProcessDuties.current));
  });
}
