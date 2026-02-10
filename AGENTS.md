# AI Agent Guidelines for Otzaria

## CRITICAL: Communication Language
**ALWAYS respond in Hebrew (עברית)!** This includes:
- All answers and explanations
- Your thinking process
- Error messages and debugging info
- Only code/comments can be in English when appropriate

## Mandatory Workflow
1. **Plan** - Create detailed action plan before execution
2. **Execute** - Step by step until completion
3. **Validate** - Run `flutter analyze` after EVERY change
4. **Fix ALL errors before proceeding to next step**
5. **Never skip validation - errors compound quickly!**

## Architecture

### Design Patterns
- **BLoC Pattern** - State management (every feature needs: bloc/event/state)
- **Repository Pattern** - Separates data access from business logic
- **Provider** - For dependency injection across the app

### Feature Structure (MUST follow)
```
lib/feature_name/
├── bloc/
│   ├── feature_bloc.dart      # Business logic
│   ├── feature_event.dart     # User actions/events
│   └── feature_state.dart     # UI states
├── models/
│   └── feature_model.dart     # Data models
├── repository/
│   └── feature_repository.dart # Data layer
└── view/
    ├── feature_screen.dart    # Main screen
    └── widgets/               # Feature-specific widgets
```

### Key Code Locations
```
lib/
├── data/repository/
│   └── books_repository.dart          # Central books management
├── models/
│   ├── books.dart                     # Book model (title, path, etc)
│   └── app_model.dart                 # Main app state
├── widgets/
│   ├── rtl_text_field.dart           # RTL text input (USE THIS!)
│   └── [other shared widgets]
├── core/
│   └── scaffold_messenger.dart        # UiSnack for messages
├── search/
│   ├── bloc/                          # Search state management
│   └── search_repository.dart         # Search engine
├── settings/
│   ├── settings_repository.dart       # App settings
│   └── bloc/
├── bookmarks/repository/              # Bookmarks system
├── history/                           # Reading history
├── personal_notes/                    # User notes feature
├── pdf_book/                          # PDF viewer screens
├── text_book/                         # Text viewer screens
└── utils/
    └── open_book.dart                 # Book opening logic
```


## MANDATORY UI Components

### 1. Icons - ONLY from `fluentui_system_icons`
```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

// Examples:
Icon(FluentIcons.search_24_regular)
Icon(FluentIcons.book_24_filled)
Icon(FluentIcons.settings_24_regular)
```
**Never use:**
- Material Icons
- Cupertino Icons
- Custom icon fonts
- Random icon packages

### 2. User Messages - ONLY via `UiSnack`
```dart
import 'package:otzaria/core/scaffold_messenger.dart';

UiSnack.show('הפעולה בוצעה');              // Success
UiSnack.showError('שגיאה בביצוע');         // Error
UiSnack.show(UiSnack.textCopied);          // Pre-defined message
```
**Never use:**
- `ScaffoldMessenger.of(context).showSnackBar()`
- Custom snackbar widgets
- Toast packages
- Alert dialogs for simple messages

### 3. Text Input - ONLY `RtlTextField`
```dart
import 'package:otzaria/widgets/rtl_text_field.dart';

RtlTextField(
  controller: _controller,
  decoration: InputDecoration(labelText: 'חיפוש'),
  onSubmitted: (value) => _handleSearch(),
  autofocus: true,
)
```
**NEVER use regular `TextField`** - it breaks RTL support!

## Code Guidelines

### RTL Support (Critical!)
Every Hebrew text MUST have:
```dart
Text(
  'טקסט עברי',
  textDirection: TextDirection.rtl,  // REQUIRED!
)
```
- Use `RtlTextField` for all text inputs
- Test UI with Hebrew text before committing
- All forms, dialogs, and lists must support RTL

### BLoC Pattern Implementation
```dart
// 1. Events - User actions
sealed class FeatureEvent extends Equatable {
  const FeatureEvent();
}

class LoadDataEvent extends FeatureEvent {
  const LoadDataEvent();
  @override
  List<Object> get props => [];
}

// 2. States - UI states
sealed class FeatureState extends Equatable {
  const FeatureState();
}

class LoadingState extends FeatureState {
  @override
  List<Object> get props => [];
}

class LoadedState extends FeatureState {
  final Data data;
  const LoadedState(this.data);
  @override
  List<Object> get props => [data];
}

// 3. Bloc - Logic
class FeatureBloc extends Bloc<FeatureEvent, FeatureState> {
  final FeatureRepository repository;
  
  FeatureBloc({required this.repository}) : super(InitialState()) {
    on<LoadDataEvent>(_onLoadData);
  }
  
  Future<void> _onLoadData(
    LoadDataEvent event,
    Emitter<FeatureState> emit,
  ) async {
    emit(LoadingState());
    try {
      final data = await repository.fetchData();
      emit(LoadedState(data));
    } catch (e) {
      emit(ErrorState(e.toString()));
      UiSnack.showError('שגיאה: ${e.toString()}');
    }
  }
}
```

### Repository Pattern
```dart
class FeatureRepository {
  final DataSource dataSource;  // Could be API, DB, file system
  
  FeatureRepository({required this.dataSource});
  
  Future<List<Item>> getItems() async {
    try {
      final rawData = await dataSource.fetch();
      return rawData.map((e) => Item.fromJson(e)).toList();
    } catch (e) {
      throw RepositoryException('Failed to get items: $e');
    }
  }
}
```

### Error Handling
```dart
try {
  await riskyOperation();
} catch (e, stackTrace) {
  // Log for debugging
  print('Error: $e\n$stackTrace');
  
  // Show user-friendly message
  UiSnack.showError('אירעה שגיאה: ${e.toString()}');
  
  // Update state if needed
  emit(ErrorState(e.toString()));
}
```

### Documentation (Hebrew for public APIs)
```dart
/// מחזירה רשימת ספרים לפי קטגוריה
/// 
/// [category] - שם הקטגוריה
/// מחזירה [Future<List<Book>>] - רשימת ספרים או שגיאה
/// זורקת [RepositoryException] אם הנתונים לא נמצאו
Future<List<Book>> getBooksByCategory(String category) async {
  // Implementation
}
```

## Testing Strategy

### Before Every Commit (MANDATORY)
```bash
flutter analyze              # Must pass with ZERO errors/warnings
flutter test test/feature/   # Run ONLY tests related to your changes
dart format lib/file.dart    # Format ONLY files you modified
```

### When to Run Which Tests
| Change Type | Tests to Run |
|-------------|--------------|
| Modified `lib/search/` | `flutter test test/search/` |
| Modified shared widget | All tests using that widget |
| New feature | All tests for that feature |
| Changed interface/contract | All affected integration tests |
| Modified core logic | Full test suite |

### Writing Tests
- **Bloc**: Use `bloc_test` package
- **Repository**: Mock dependencies with `mockito`
- **Always add/update tests** for code you change
- Example:
```dart
blocTest<SearchBloc, SearchState>(
  'emits SearchLoaded when search succeeds',
  build: () => SearchBloc(repository: mockRepository),
  act: (bloc) => bloc.add(SearchRequested('query')),
  expect: () => [SearchLoading(), SearchLoaded(results)],
);
```

## Essential Commands
```bash
flutter pub get              # Install dependencies
flutter pub outdated         # Check for updates
dart fix --apply            # Auto-fix common issues
flutter clean && flutter pub get  # Nuclear option for build issues
```

## Platform Support
**Supported:** Windows, Linux, Android, iOS, macOS

Use platform checks when needed:
```dart
import 'dart:io';

if (Platform.isAndroid || Platform.isIOS) {
  // Mobile-specific code
} else {
  // Desktop-specific code
}
```

## Pre-Commit Checklist
- [ ] `flutter analyze` passes (zero errors/warnings)
- [ ] Relevant tests pass
- [ ] Formatted modified files with `dart format`
- [ ] Added/updated tests for changes
- [ ] Documented new public functions (in Hebrew)
- [ ] RTL support verified for Hebrew UI
- [ ] Used `RtlTextField` (not `TextField`)
- [ ] Used `fluentui_system_icons` for icons
- [ ] Used `UiSnack` for messages
- [ ] Works on all target platforms

## Golden Rules

### Non-Negotiable Requirements
1. **No progression with errors** - Fix ALL analyzer errors before next step
2. **Run `flutter analyze` after EVERY file change** - Don't accumulate errors
3. **RTL text fields** - Use `RtlTextField` exclusively, never `TextField`
4. **Icons** - Only `fluentui_system_icons`, no exceptions
5. **User messages** - Only through `UiSnack`, never direct SnackBar
6. **Hebrew text** - Always include `textDirection: TextDirection.rtl`
7. **Test coverage** - Add/update tests for every code change
8. **Documentation** - Document all public APIs in Hebrew
9. **Cross-platform** - Code must work on all supported platforms
10. **Pre-commit trinity** - `analyze` + `test` + `format` = mandatory

### Common Mistakes to Avoid
- Using `TextField` instead of `RtlTextField`
- Using Material/Cupertino icons instead of FluentUI
- Showing messages without `UiSnack`
- Forgetting `textDirection: TextDirection.rtl` on Hebrew text
- Skipping `flutter analyze` before committing
- Running full test suite instead of relevant tests
- Formatting entire project instead of modified files
- Moving to next feature while current code has warnings
- Not testing on multiple platforms
- Hardcoding platform-specific paths

---

**זכור: תמיד ענה בעברית!**
