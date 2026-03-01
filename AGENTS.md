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

## Bug Fix Workflow (MANDATORY)

**Primary rule: Investigate first, ask only if you truly must.**

Before writing any fix, perform the following steps **on your own** without asking the user:

1. **Understand the symptom** - What did the user report? If critical details are missing that are needed to *execute* the fix (not to analyze) - ask everything **in a single message**.
2. **Investigate git** - Run `git log --oneline -20` and check commits that touched relevant code.
3. **Read the code** - Read the code before proposing any fix. Don't assume, know.
4. **Identify the root cause** - If found, explain to the user what caused the bug before fixing it.

### Decision Tree

```
User reports bug
       │
       ▼
  Investigate first:
  git log + read code
       │
       ▼
 Root cause found?
   ┌───┴───┐
  YES      NO
   │           │
   ▼           ▼
Apply MINIMAL  Ask user ONE message
fix & explain  with ALL missing info
               then investigate again
```

### Fix Philosophy - CRITICAL

**Bug fix ≠ adding code!**

- **FIRST** - try to **remove** or **revert** code that caused the bug
- **SECOND** - try to **change** existing logic minimally
- **LAST RESORT** - add new code, only if truly necessary
- Adding more code to work around a bug = introducing future bugs

### Red Flags - Stop and Ask

If you find yourself about to:
- Add a `try/catch` to silence an error → find out *why* the error occurs first
- Add a null check that "shouldn't be needed" → find out *why* it's null
- Add a workaround flag/boolean → reconsider the root cause
- Write more than ~15 lines to fix a single bug → something is wrong, reassess

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

### 4. Dialogs - ONLY from `custom_ui_components`
```dart
import 'package:otzaria/widgets/custom_ui_components.dart';

// דיאלוג עם כפתור אחד (אישור בלבד)
showSingleActionDialog(
  context: context,
  title: 'כותרת',
  content: 'תוכן הדיאלוג',
  confirmText: 'אישור',
);

// דיאלוג עם שני כפתורים (ביטול ואישור)
showTwoActionsDialog(
  context: context,
  title: 'כותרת',
  content: 'תוכן הדיאלוג',
  cancelText: 'ביטול',
  confirmText: 'אישור',
);

// דיאלוג אזהרה (המשתמש צריך לבטל באופן אידיאלי)
showWarningDialog(
  context: context,
  title: 'אזהרה',
  content: 'פעולה זו היא סופית',
  subtitle: 'שים לב שלא ניתן לבטל פעולה זו',  // טקסט באדום
  cancelText: 'ביטול',
  confirmText: 'המשך',
);
```

**Dialog Styling Rules (CRITICAL):**
- **SingleActionDialog**: כפתור אחד - FilledButton (primary/onPrimary)
- **TwoActionsDialog**: 
  - Cancel = FilledButton.tonal (surfaceContainerHighest/onSurface)
  - Confirm = FilledButton (primary/onPrimary)
- **WarningDialog**: 
  - Cancel = FilledButton (primary/onPrimary) - recommended (safe choice)
  - Confirm = TextButton (transparent background, error text color) - dangerous
  - Subtitle = error color (red)

**Never use:**
- `showDialog` with custom `AlertDialog` directly
- Material `SimpleDialog`
- Custom dialog widgets without the standard styling
- Hardcoded colors (Colors.red, Colors.blue, etc.)

### 5. Action Buttons - ONLY from `custom_ui_components`
```dart
import 'package:otzaria/widgets/custom_ui_components.dart';

// כפתור לפעולה מומלצת (Primary style)
RecommendedActionButton(
  text: 'שנה מיקום',
  onPressed: () => _changeLocation(),
  isLoading: false,  // אופציונלי - להצגת אינדיקטור טעינה
);

// כפתור לפעולה ניטרלית/לא מומלצת (Tonal style)
NeutralActionButton(
  text: 'איפוס',
  onPressed: () => _resetSettings(),
  isLoading: false,  // אופציונלי - להצגת אינדיקטור טעינה
);
```

**Button Styling Rules (CRITICAL):**
- **RecommendedActionButton**: FilledButton (primary background, onPrimary text)
- **NeutralActionButton**: FilledButton.tonal (surfaceContainerHighest background, onSurface text)
- **NEVER use hardcoded colors** - always use `Theme.of(context).colorScheme`

**When to use which button:**
- `RecommendedActionButton` - recommended actions (change settings, choose location, update, add)
- `NeutralActionButton` - neutral or dangerous actions (reset, delete, remove, stop)

**Never use:**
- `ElevatedButton`, `TextButton`, `OutlinedButton` directly
- Custom button widgets without the standard styling
- Material `IconButton` for primary actions
- Hardcoded colors

### 6. Settings Cards - ONLY `SettingsCard`
```dart
import 'package:otzaria/settings/settings_card.dart';

SettingsCard(
  title: 'כותרת הקטגוריה',
  subtitle: 'תיאור אופציונלי',  // אופציונלי
  children: [
    ListTile(...),
    // Divider מתווסף אוטומטית בין פריטים
    SwitchListTile(...),
  ],
);
```

**Card Styling Rules:**
- Title: titleMedium, bold, primary color
- Subtitle: bodySmall, onSurfaceVariant color (optional)
- Card: surface color, rounded corners (20), subtle border
- Dividers: Automatic between children, surfaceContainerHighest color, thickness 1.5

**Hover Effects:**
- Remove hover from ListTile rows containing action buttons: `hoverColor: Colors.transparent`
- Hover should ONLY appear on the action buttons themselves
- This prevents double-hover effect and improves UX

### 7. Segmented Settings - ONLY `SegmentedSettingsTile`
```dart
import 'package:otzaria/widgets/custom_ui_components.dart';

// הגדרה עם 2-4 אפשרויות
SegmentedSettingsTile<String>(
  icon: FluentIcons.text_font_info_24_regular,
  title: 'הצגת הניקוד',
  subtitle: 'הניקוד יוצג בכל הספרים',
  options: const [
    SegmentOption(value: 'always', label: 'הצג תמיד'),
    SegmentOption(value: 'tanach_only', label: 'הצג בתנ"ך'),
    SegmentOption(value: 'never', label: 'אל תציג'),
  ],
  currentValue: nikudDisplayMode,
  onChanged: (value) {
    // עדכון ה-BLoC
  },
);
```

**When to use SegmentedSettingsTile:**
- Settings with 2-4 mutually exclusive options
- When the user needs to pick exactly one value from a small set
- Modern alternative to a RadioButton group or multiple SwitchListTiles

**Styling:**
- Selected: primary color with 20% opacity background
- Unselected: card color background
- Rounded corners (8)
- Fits in single row within SettingsCard

**Title can be:**
- String - plain text
- Widget - for advanced styling (e.g. RichText with mixed colors)

**Never use:**
- RadioButton groups for 2-4 options
- Multiple SwitchListTile for mutually exclusive options
- Custom segmented button implementations

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

class InitialState extends FeatureState {
  @override
  List<Object> get props => [];
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
  debugPrint('Error: $e\n$stackTrace');
  
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

## Golden Rules

### Non-Negotiable Requirements
1. **No progression with errors** - Fix ALL analyzer errors before next step
2. **Run `flutter analyze` after EVERY file change** - Don't accumulate errors
3. **RTL text fields** - Use `RtlTextField` exclusively, never `TextField`
4. **Icons** - Only `fluentui_system_icons`, no exceptions
5. **User messages** - Only through `UiSnack`, never direct SnackBar
6. **Dialogs** - Only through `custom_ui_components` (SingleActionDialog, TwoActionsDialog, WarningDialog)
7. **Action buttons** - Only `RecommendedActionButton` or `NeutralActionButton` from `custom_ui_components`
8. **Settings cards** - Only `SettingsCard` from `settings_card.dart`
9. **Color theming** - NEVER use hardcoded colors (Colors.red, Colors.blue, etc.), ALWAYS use `Theme.of(context).colorScheme`
10. **Hover effects** - Remove from ListTile rows with buttons (`hoverColor: Colors.transparent`)
11. **Hebrew text** - Always include `textDirection: TextDirection.rtl`
12. **Test coverage** - Add/update tests for every code change
13. **Documentation** - Document all public APIs in Hebrew
14. **Cross-platform** - Code must work on all supported platforms
15. **Pre-commit trinity** - `analyze` + `test` + `format` = mandatory

### Common Mistakes to Avoid
- Fixing a bug by adding code instead of finding and removing the root cause
- Patching around a null/error with defensive code without understanding why it occurs
- Asking the user questions that could be answered by reading the code or git history
- Asking multiple separate questions instead of batching all open questions into one message
- Writing a large diff to fix what should be a small bug
- Using `TextField` instead of `RtlTextField`
- Using Material/Cupertino icons instead of FluentUI
- Showing messages without `UiSnack`
- Using custom dialogs instead of `custom_ui_components` dialogs
- Using `ElevatedButton`/`TextButton` instead of `RecommendedActionButton`/`NeutralActionButton`
- Using hardcoded colors instead of `Theme.of(context).colorScheme`
- Not removing hover effects from ListTile rows with action buttons
- Forgetting `textDirection: TextDirection.rtl` on Hebrew text
- Skipping `flutter analyze` before committing
- Running full test suite instead of relevant tests
- Formatting entire project instead of modified files
- Moving to next feature while current code has warnings
- Not testing on multiple platforms
- Hardcoding platform-specific paths
- Creating unnecessary MD files to document changes (CHANGES.md, SUMMARY.md, etc.)

---

**זכור: תמיד ענה בעברית!**
