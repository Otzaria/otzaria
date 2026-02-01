import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/editing/repository/local_overrides_repository.dart';
import 'package:otzaria/text_book/editing/models/editor_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalOverridesRepository', () {
    late LocalOverridesRepository repository;

    setUp(() {
      repository = LocalOverridesRepository(
        settings: const EditorSettings(),
      );
    });

    group('Override Operations', () {
      test('should write and read override', () async {
        const bookId = 'test_book';
        const sectionId = 'test_section';
        const markdown = '# Test Content\nThis is a test.';
        const sourceHash = 'abc123';

        await repository.writeOverride(bookId, sectionId, markdown, sourceHash);
        final override = await repository.readOverride(bookId, sectionId);

        expect(override, isNotNull);
        expect(override!.markdownContent, equals(markdown));
        expect(override.sourceHashOnOpen, equals(sourceHash));
      }, skip: 'Requires platform plugin for path_provider');

      test('should return null for non-existent override', () async {
        final override =
            await repository.readOverride('nonexistent', 'section');
        expect(override, isNull);
      }, skip: 'Requires platform plugin for path_provider');

      test('should delete override', () async {
        const bookId = 'test_book';
        const sectionId = 'test_section';
        const markdown = '# Test Content';
        const sourceHash = 'abc123';

        await repository.writeOverride(bookId, sectionId, markdown, sourceHash);
        await repository.deleteOverride(bookId, sectionId);

        final override = await repository.readOverride(bookId, sectionId);
        expect(override, isNull);
      }, skip: 'Requires platform plugin for path_provider');
    });

    group('Draft Operations', () {
      test('should write and read draft', () async {
        const bookId = 'test_book';
        const sectionId = 'test_section';
        const markdown = '# Draft Content\nThis is a draft.';

        await repository.writeDraft(bookId, sectionId, markdown);
        final draft = await repository.readDraft(bookId, sectionId);

        expect(draft, isNotNull);
        expect(draft!.markdownContent, equals(markdown));
      }, skip: 'Requires platform plugin for path_provider');

      test('should delete draft', () async {
        const bookId = 'test_book';
        const sectionId = 'test_section';
        const markdown = '# Draft Content';

        await repository.writeDraft(bookId, sectionId, markdown);
        await repository.deleteDraft(bookId, sectionId);

        final draft = await repository.readDraft(bookId, sectionId);
        expect(draft, isNull);
      }, skip: 'Requires platform plugin for path_provider');

      test('should detect newer draft than override', () async {
        const bookId = 'test_book';
        const sectionId = 'test_section';

        // Write override first
        await repository.writeOverride(
            bookId, sectionId, '# Override', 'hash1');

        // Wait a bit to ensure different timestamps
        await Future.delayed(const Duration(milliseconds: 10));

        // Write draft after override
        await repository.writeDraft(bookId, sectionId, '# Draft');

        final hasNewerDraft =
            await repository.hasNewerDraftThanOverride(bookId, sectionId);
        expect(hasNewerDraft, isTrue);
      }, skip: 'Requires platform plugin for path_provider');
    });

    group('Listing Operations', () {
      test('should list overrides for book', () async {
        const bookId = 'test_book';

        await repository.writeOverride(
            bookId, 'section1', '# Content 1', 'hash1');
        await repository.writeOverride(
            bookId, 'section2', '# Content 2', 'hash2');

        final overrides = await repository.listOverrides(bookId);
        expect(overrides, hasLength(2));
        expect(overrides, containsAll(['section1', 'section2']));
      }, skip: 'Requires platform plugin for path_provider');

      test('should list drafts for book', () async {
        const bookId = 'test_book';

        await repository.writeDraft(bookId, 'section1', '# Draft 1');
        await repository.writeDraft(bookId, 'section2', '# Draft 2');

        final drafts = await repository.listDrafts(bookId);
        expect(drafts, hasLength(2));
        expect(drafts, containsAll(['section1', 'section2']));
      }, skip: 'Requires platform plugin for path_provider');
    });

    group('Links File Detection', () {
      test('should detect links file existence', () async {
        // This test would need to be adapted based on actual file structure
        final hasLinks = await repository.hasLinksFile('test_book');
        expect(hasLinks, isA<bool>());
      }, skip: 'Requires platform plugin for path_provider');
    });
  });
}
