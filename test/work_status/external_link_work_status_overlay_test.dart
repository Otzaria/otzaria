import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/external_link_work_status.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';

class _FakeLinks extends ExternalLinkRepository {
  final calls = <String>[];

  @override
  void pauseBuild() {
    calls.add('pause');
    buildPaused.value = true;
  }

  @override
  void resumeBuild() {
    calls.add('resume');
    buildPaused.value = false;
  }

  @override
  void setBuildEconomy(bool on) {
    calls.add('economy:$on');
    buildEconomy.value = on;
  }
}

const _booksItem = WorkStatusItem(
  id: 'indexing',
  title: 'אינדוקס ספרים',
  message: 'התוכנה בתהליך אינדוקס',
  detail: 'התקדמות: 133/1633',
  progress: 0.08,
);

void main() {
  late _FakeLinks links;
  late WorkStatusCubit cubit;
  late ExternalLinkWorkStatusReporter reporter;

  setUp(() {
    links = _FakeLinks();
    cubit = WorkStatusCubit();
    reporter = ExternalLinkWorkStatusReporter(
      repository: links,
      upsert: cubit.upsert,
      remove: cubit.remove,
    );
  });

  tearDown(() {
    reporter.dispose();
    return cubit.close();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: const MaterialApp(
        home: Scaffold(body: Stack(children: [WorkStatusOverlay()])),
      ),
    ),
  );

  void startBuild() {
    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1500000, total: 2167384),
    };
  }

  testWidgets('לבדו: תצוגה מלאה עם הטקסט והמספרים; נעלם בסיום', (tester) async {
    await pump(tester);
    expect(find.text('אינדוקס קישורים'), findsNothing);

    startBuild();
    await tester.pump();
    expect(find.text('אינדוקס קישורים'), findsOneWidget);
    expect(find.text('הקישורים בתהליך אינדוקס'), findsOneWidget);
    expect(find.text('התקדמות: 1,500,000/2,167,384'), findsOneWidget);
    expect(find.text('69%'), findsOneWidget);

    links.buildProgress.value = const {};
    await tester.pump();
    await tester.pump();
    expect(find.text('אינדוקס קישורים'), findsNothing);
    expect(cubit.state.hasActiveItems, isFalse);
  });

  testWidgets('יחד עם אינדוקס הספרים: שורות באותו כרטיס', (tester) async {
    cubit.upsert(_booksItem);
    await pump(tester);
    startBuild();
    await tester.pump();

    expect(find.text('אינדוקס ספרים'), findsOneWidget);
    expect(find.text('אינדוקס קישורים'), findsOneWidget);
    expect(find.byType(DecoratedBox), findsWidgets);
    expect(find.byTooltip('סגור'), findsOneWidget);
  });

  testWidgets('סגירה בכרטיס מסתירה את הכול לפי המנגנון הקיים', (tester) async {
    cubit.upsert(_booksItem);
    await pump(tester);
    startBuild();
    await tester.pump();

    await tester.tap(find.byTooltip('סגור'));
    await tester.pump();
    expect(cubit.state.isDismissed, isTrue);
    expect(find.text('אינדוקס קישורים'), findsNothing);
  });

  testWidgets('השהה, המשך ומצב חסכוני קוראים ל-API', (tester) async {
    await pump(tester);
    startBuild();
    await tester.pump();

    await tester.tap(find.text('השהה'));
    await tester.pump();
    expect(links.calls, ['pause']);
    expect(find.text('האינדוקס מושהה'), findsOneWidget);

    await tester.tap(find.text('המשך'));
    await tester.pump();
    expect(links.calls, ['pause', 'resume']);

    await tester.tap(find.text('מצב חסכוני'));
    await tester.pump();
    expect(links.calls.last, 'economy:true');
    expect(links.buildEconomy.value, isTrue);
  });
}
