import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  test('תג היעד: מצעד הדלתא האחרון, אחרת מה-DB המלא', () {
    const manifest = DeltaManifest(
      fromVersion: 29,
      toVersion: 30,
      fromSchemaVersion: 5,
      toSchemaVersion: 5,
      fromContentHash: 'a',
      toContentHash: 'b',
      patchFiles: [],
    );
    final delta = LibraryUpdatePlan.delta(
      localVersion: 29,
      targetVersion: 30,
      steps: const [
        PatchEdge(
          manifest: manifest,
          patchFileUrls: {},
          manifestUrl:
              'https://github.com/Otzaria/SeforimLibrary/releases/download/'
              'v30-20260930165019/patch-v29-v30.db.zst.manifest.json',
        ),
      ],
    );
    final full = LibraryUpdatePlan.fullDownload(
      localVersion: 0,
      targetVersion: 30,
      asset: const ReleaseAsset(
        name: 'seforim.db.zst',
        downloadUrl: '',
        size: 1,
      ),
      releaseTag: 'v30-20260930165019',
    );

    expect(LibraryUpdateBloc.libraryTagOf(delta), 'v30-20260930165019');
    expect(LibraryUpdateBloc.libraryTagOf(full), 'v30-20260930165019');
    expect(
      LibraryUpdateBloc.libraryTagOf(LibraryUpdatePlan.none(localVersion: 30)),
      isNull,
    );
  });
}
