# AI Agent Guidelines for Working with Otzaria Project

## Communication Guidelines

**IMPORTANT: Always respond in Hebrew. Display your thinking process in Hebrew as well.**

Even though this document is in English for reference, when working on this project:
- Write all responses to users in Hebrew
- Show your reasoning and thought process in Hebrew
- Use Hebrew for explanations and summaries
- Only code comments and technical documentation may be in English when appropriate

## General Principles

### Execution Planning
1. **Plan a detailed action plan before starting execution**
2. **Execute the plan step by step until completion**
3. **After each action, run `flutter analyze` to check for errors and warnings**
4. **If there are errors, fix them before continuing**
5. **Do not move to the next step before the current step works without errors**

### Development Environment Tips
- Use `flutter pub get` after every change to `pubspec.yaml`
- Run `flutter clean` if there are strange build issues
- Use `flutter pub outdated` to check for outdated dependencies
- Check the package name in `pubspec.yaml` - the name is `otzaria`
- Use `dart fix --apply` for automatic fixing of common issues

### Architecture
- The project uses **BLoC pattern** for state management
- The project uses **Repository pattern** to separate business logic from data sources
- Each feature should be organized in its own folder with the following structure:
  ```
  feature_name/
  ├── bloc/
  │   ├── feature_bloc.dart
  │   ├── feature_event.dart
  │   └── feature_state.dart
  ├── models/
  ├── repository/
  └── view/
  ```

## Mandatory UI Components

### Icons
**MUST use icons only from the `fluentui_system_icons` library**

```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

// Usage examples:
Icon(FluentIcons.search_24_regular)
Icon(FluentIcons.book_24_filled)
Icon(FluentIcons.settings_24_regular)
Icon(FluentIcons.copy_24_regular)
Icon(FluentIcons.delete_24_regular)
```

### User Messages
**Every user message MUST be through `UiSnack` from `lib/core/scaffold_messenger.dart`**

```dart
import 'package:otzaria/core/scaffold_messenger.dart';

// Regular message
UiSnack.show('הפעולה בוצעה בהצלחה');

// Error message
UiSnack.showError('אירעה שגיאה');

// Message with custom color
UiSnack.showSuccess('הנתונים נשמרו', backgroundColor: Colors.green);

// Message with action
UiSnack.showWithAction(
  message: 'הקובץ נמחק',
  actionLabel: 'בטל',
  onAction: () {
    // Code to undo action
  },
);

// Using predefined messages
UiSnack.show(UiSnack.textCopied);
UiSnack.show(UiSnack.savedSuccessfully);
```

### Text Input Fields
**Every text input field MUST use `RtlTextField` from `lib/widgets/rtl_text_field.dart`**

```dart
import 'package:otzaria/widgets/rtl_text_field.dart';

RtlTextField(
  controller: _controller,
  decoration: InputDecoration(
    labelText: 'חיפוש',
    hintText: 'הקלד טקסט לחיפוש',
  ),
  onChanged: (value) {
    // Handle change
  },
  onSubmitted: (value) {
    // Handle submission
  },
  autofocus: true,
)
```

**Do NOT use Flutter's regular `TextField`!** Always use `RtlTextField` to properly support RTL.

## Common Functions and Services

### Book Management
```dart
// lib/data/repository/books_repository.dart - Access to books repository
// lib/models/books.dart - Book model
// lib/utils/open_book.dart - Opening a book
```

### Search
```dart
// lib/search/search_repository.dart - Search engine
// lib/search/bloc/ - BLoC for search state management
```

### Settings
```dart
// lib/settings/settings_repository.dart - Access to settings
// lib/settings/settings_bloc.dart - BLoC for settings management
```

### Bookmarks and History
```dart
// lib/bookmarks/repository/bookmarks_repository.dart - Bookmarks management
// lib/history/history_repository.dart - History management
```

### Personal Notes
```dart
// lib/personal_notes/personal_notes_system.dart - Personal notes system
// lib/personal_notes/repository/ - Repository for notes
```

### PDF
```dart
// lib/pdf_book/pdf_book_screen.dart - PDF view
// lib/pdf_book/bloc/ - BLoC for PDF management
```

### Text
```dart
// lib/text_book/text_book_repository.dart - Repository for text books
// lib/text_book/bloc/ - BLoC for text books management
```

## Code Rules

### RTL (Right-to-Left)
- **All Hebrew texts must have `textDirection: TextDirection.rtl`**
- Use `RtlTextField` instead of `TextField`
- Check that the interface looks correct in Hebrew

### Bloc Pattern
```dart
// Event
abstract class FeatureEvent extends Equatable {
  const FeatureEvent();
  
  @override
  List<Object?> get props => [];
}

// State
abstract class FeatureState extends Equatable {
  const FeatureState();
  
  @override
  List<Object?> get props => [];
}

// Bloc
class FeatureBloc extends Bloc<FeatureEvent, FeatureState> {
  final FeatureRepository repository;
  
  FeatureBloc({required this.repository}) : super(FeatureInitial()) {
    on<FeatureEventName>(_onEventName);
  }
  
  Future<void> _onEventName(
    FeatureEventName event,
    Emitter<FeatureState> emit,
  ) async {
    // Logic
  }
}
```

### Repository Pattern
```dart
class FeatureRepository {
  final DataProvider dataProvider;
  
  FeatureRepository({required this.dataProvider});
  
  Future<Result> fetchData() async {
    try {
      // Logic
      return result;
    } catch (e) {
      throw Exception('Error: $e');
    }
  }
}
```

### Error Handling
```dart
try {
  // Code that might throw an error
} catch (e) {
  UiSnack.showError('אירעה שגיאה: ${e.toString()}');
  // Additional error handling
}
```

## Testing

### Testing Instructions
- **Before every commit, run only the relevant tests for your changes**
- Run `flutter analyze` to check for static errors
- Run specific tests related to the code you modified
- Run `dart format .` to format code
- Fix every error or warning before continuing
- **Add or update tests for code you change, even if not requested**

### Running Tests
```bash
# Check for errors and warnings - mandatory before commit
flutter analyze

# Run only relevant tests for your changes (RECOMMENDED)
# Example: If you changed search functionality
flutter test test/search/

# Run specific test file
flutter test test/path/to/test_file.dart

# Run test with specific name pattern
flutter test --name "test name pattern"

# Run all tests (only if you made broad changes)
flutter test

# Check code format
dart format --set-exit-if-changed .

# Auto-fix format
dart format .

# Check dependencies
flutter pub outdated

# Clean and rebuild (if there are issues)
flutter clean && flutter pub get
```

### How to Identify Relevant Tests
1. **Direct changes**: If you modified `lib/search/search_bloc.dart`, run `flutter test test/search/`
2. **Feature changes**: If you changed bookmarks feature, run all bookmark tests
3. **Shared utilities**: If you modified shared code (like `RtlTextField`), run tests that use it
4. **Breaking changes**: If you changed interfaces or contracts, run all affected tests
5. **New features**: Run tests for the new feature and any integration tests

### Writing Tests
- Write tests for Bloc using `bloc_test`
- Write tests for Repository
- Use `mockito` for mocking
- Every new feature should include tests
- Update existing tests if you changed behavior

## Code Conventions

### File Names
- Dart files: `snake_case.dart`
- Model files: `model_name.dart`
- Bloc files: `feature_bloc.dart`, `feature_event.dart`, `feature_state.dart`

### Variable Names
- Variables: `camelCase`
- Constants: `UPPER_SNAKE_CASE`
- Classes: `PascalCase`

### Documentation
- Add documentation to every public function
- Use Hebrew for documentation
- Add usage examples when needed

```dart
/// Returns list of books by category
///
/// [category] - Category name
/// Returns [List<Book>] - List of books
Future<List<Book>> getBooksByCategory(String category) async {
  // Code
}
```

## Dependencies

### Main Dependencies
- `flutter_bloc` - State management
- `equatable` - Object comparison
- `isar` - Local database
- `pdfrx` - PDF viewer
- `fluentui_system_icons` - Icons
- `provider` - Dependency injection
- `path_provider` - Access to system folders

### Adding New Dependency
1. Add to `pubspec.yaml`
2. Run `flutter pub get`
3. Ensure dependency is compatible with Flutter 3.x

## Platforms

The project supports:
- Windows
- Linux
- Android
- iOS
- macOS

**Note:** Written code must work on all platforms. Use `Platform.isAndroid`, `Platform.isWindows`, etc. when needed.

## Accessibility

- Ensure all buttons have `Semantics` or `Tooltip`
- Use appropriate font sizes
- Ensure good color contrast
- Support screen readers

## Performance

- Use `const` constructors when possible
- Use `ListView.builder` instead of `ListView` for long lists
- Use `FutureBuilder` or `StreamBuilder` for async loading
- Avoid unnecessary `setState`

## Pull Request Instructions

### Title Format
```
[<feature_name>] <Change description>
```

Examples:
- `[search] Add search with nikud`
- `[pdf] Fix zoom bug`
- `[ui] Improve RTL display`

### Before Submitting PR
1. **Run `flutter analyze` - must have no errors or warnings**
2. **Run relevant tests for your changes - all must pass**
3. **Run `dart format .` - code must be formatted**
4. **Check that code works on all relevant platforms**
5. **Ensure you added/updated tests for your changes**
6. **Write clear description of what you changed and why**

### Checklist Before Commit
- [ ] `flutter analyze` passes without errors
- [ ] Relevant tests pass without errors (run `flutter test test/path/to/relevant/`)
- [ ] `dart format .` was run
- [ ] I added/updated tests
- [ ] I added documentation to new functions
- [ ] I checked that code works in practice
- [ ] Code supports RTL
- [ ] I used `RtlTextField` not `TextField`
- [ ] I used `fluentui_system_icons` for icons
- [ ] I used `UiSnack` for messages

## Useful Commands

### Dependency Management
```bash
# Install dependencies
flutter pub get

# Update dependencies
flutter pub upgrade

# Check outdated dependencies
flutter pub outdated

# Add new dependency
flutter pub add <package_name>

# Remove dependency
flutter pub remove <package_name>
```

### Build and Run
```bash
# Run in debug mode
flutter run

# Run on specific device
flutter run -d <device_id>

# List available devices
flutter devices

# Build for Windows
flutter build windows

# Build for Android
flutter build apk

# Build for Linux
flutter build linux
```

### Cleanup and Maintenance
```bash
# Clean build cache
flutter clean

# Clean and rebuild
flutter clean && flutter pub get

# Auto-fix common issues
dart fix --apply

# Check Flutter health
flutter doctor

# Update Flutter
flutter upgrade
```

## Workflow Summary

1. **Understand the requirement** - Read and understand what needs to be done
2. **Plan** - Write detailed action plan with clear steps
3. **Execute step by step** - Write clean and documented code, check each step before continuing
4. **Check** - Run `flutter analyze` and fix every error or warning
5. **Test** - Run relevant tests for your changes and ensure everything works
6. **Format** - Run `dart format .`
7. **Document** - Add documentation and comments in Hebrew
8. **Test in practice** - Run the application and ensure changes work
9. **Review** - Go over the code and ensure it meets all standards

---

## Golden Rules

1. **Do not move to next step if there are errors in current step**
2. **Always run `flutter analyze` after changes**
3. **Use only `RtlTextField`, never regular `TextField`**
4. **Use only icons from `fluentui_system_icons`**
5. **Every user message through `UiSnack` only**
6. **Every Hebrew text with `textDirection: TextDirection.rtl`**
7. **Add tests for all new code**
8. **Document every public function in Hebrew**
9. **Code must work on all platforms (Windows, Linux, Android, iOS, macOS)**
10. **Before commit: analyze + relevant tests + format = mandatory!**

---

## REMEMBER: Communication Language

**Always respond in Hebrew (עברית) when working on this project!**

This includes:
- All responses to users
- Explanations of your work
- Your thought process
- Summaries and conclusions
- Error messages and debugging information

Only technical code and this reference document are in English.

---

**Remember:** Good code is code that's easy to read, maintain, and extend. Write code as if the next programmer who reads it is a violent psychopath who knows where you live. 😊
