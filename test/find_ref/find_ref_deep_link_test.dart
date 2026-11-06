import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/find_ref_deep_link.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

import '../helpers/memory_settings_cache.dart';

class _FakeRepository implements FindRefRepository {
  final List<String> queries = [];

  @override
  bool get respectHiddenLibrary => false;

  @override
  Stream<void> get userBooksChanges => const Stream.empty();

  @override
  void cancelPendingSearch() {}

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    queries.add(ref);
    return [DbReferenceResult(title: ref, reference: ref, segment: 1)];
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  late _FakeRepository repository;
  late FindRefBloc bloc;
  late TextEditingController controller;
  late List<bool> openCalls;

  setUp(() {
    repository = _FakeRepository();
    bloc = FindRefBloc(findRefRepository: repository);
    controller = TextEditingController(text: 'שאילתה קודמת');
    openCalls = [];
  });

  tearDown(() async {
    await bloc.close();
    controller.dispose();
  });

  void run(String query) => runDetectionDeepLink(
    query,
    controller: controller,
    bloc: bloc,
    openDialog: ({required closeIfOpen}) => openCalls.add(closeIfOpen),
  );

  test('דיאלוג פתוח אינו נסגר: הפתיחה מתבקשת בלי closeIfOpen', () async {
    run('בראשית');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(openCalls, [false]);
    expect(controller.text, 'בראשית');
    expect(repository.queries, ['בראשית']);
  });

  test('q ריק מנקה תוצאות קודמות ואת השדה', () async {
    bloc.emit(
      const FindRefSuccess([
        DbReferenceResult(title: 'ישן', reference: 'ישן', segment: 1),
      ], query: 'ישן'),
    );

    run('');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(controller.text, isEmpty);
    expect(bloc.state, isA<FindRefInitial>());
    expect(repository.queries, isEmpty);
    expect(openCalls, [false]);
  });
}
