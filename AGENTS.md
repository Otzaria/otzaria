# AI Agent Guidelines for Otzaria

## CRITICAL: Communication Language
**ALWAYS respond in Hebrew!** This includes:
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
import 'package:otzaria/widgets/misc/rtl_icon.dart';

// Regular icon (symmetric, no RTL flipping needed):
Icon(FluentIcons.search_24_regular)
Icon(FluentIcons.settings_24_regular)

// RtlIcon — ONLY for icons registered in lib/widgets/misc/rtl_icon.dart:
RtlIcon(FluentIcons.book_24_filled)              // in _flippableIcons
RtlIcon(FluentIcons.arrow_left_24_regular)        // in _fluentMirrorMap — auto-mirrors to arrow_right in RTL
RtlIcon(FluentIcons.chevron_right_24_regular)     // in _fluentMirrorMap
```

**When to use `RtlIcon` vs `Icon`:**

| Icon is registered in `rtl_icon.dart`? | Use |
|---|---|
| Yes (in `_fluentMirrorMap`, `_materialMirrorMap`, or `_flippableIcons`) | `RtlIcon(...)` |
| No | `Icon(...)` — plain, no wrapper |

**Icons currently registered in `lib/widgets/misc/rtl_icon.dart`:**

*`_fluentMirrorMap` (swaps to opposite-direction variant in RTL):*
- `chevron_right/left_24/20/16_regular`
- `arrow_right/left_24_regular`, `arrow_right/left_24_filled`
- `panel_left/right_24_regular`, `panel_left/right_24_filled`
- `text_align_right/left_24_regular`

*`_materialMirrorMap` (Material icons, swaps in RTL):*
- `arrow_forward/back`, `arrow_forward/back_ios`
- `arrow_right/left`, `chevron_right/left`
- `navigate_next/before`, `keyboard_arrow_right/left`
- `first_page/last_page`, `skip_next/previous`

*`_flippableIcons` (geometrically flipped in RTL — no opposite-direction variant in library):*
- `book_24_regular`, `book_24_filled`
- `book_information_24_regular`
- `text_align_distributed_24_regular`

**If you need to flip an icon that is NOT yet registered:**
Add it to the appropriate set/map in `lib/widgets/misc/rtl_icon.dart`, then use `RtlIcon`. Do NOT add manual `Transform.flip`/`Transform.scale` in feature files.

**Never use:**
- Material Icons (unless in `_materialMirrorMap` above)
- Cupertino Icons
- Custom icon fonts
- Random icon packages
- `mirrorIcon` parameter on any widget — **FORBIDDEN**, removed in commit 3b4d357
- Manual `Transform.scale(scaleX: -1, ...)` or `Transform.flip(flipX: true, ...)` around icons — register in `rtl_icon.dart` instead

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
import 'package:otzaria/widgets/widgets_exports.dart';

// Single button dialog (confirm only)
showSingleActionDialog(
  context: context,
  title: 'כותרת',
  content: 'תוכן הדיאלוג',
  confirmText: 'אישור',
);

// Two-button dialog (cancel + confirm)
showTwoActionsDialog(
  context: context,
  title: 'כותרת',
  content: 'תוכן הדיאלוג',
  cancelText: 'ביטול',
  confirmText: 'אישור',
);

// Warning dialog (user should ideally cancel)
showWarningDialog(
  context: context,
  title: 'אזהרה',
  content: 'פעולה זו היא סופית',
  subtitle: 'שים לב שלא ניתן לבטל פעולה זו',  // red text
  cancelText: 'ביטול',
  confirmText: 'המשך',
);
```

**Dialog Styling Rules (CRITICAL):**
- **SingleActionDialog**: single button - FilledButton (primary/onPrimary)
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
import 'package:otzaria/widgets/widgets_exports.dart';

// Recommended action button (Primary style)
RecommendedActionButton(
  text: 'שנה מיקום',
  onPressed: () => _changeLocation(),
  isLoading: false,  // optional - shows loading indicator
);

// Neutral/non-recommended action button (Tonal style)
NeutralActionButton(
  text: 'איפוס',
  onPressed: () => _resetSettings(),
  isLoading: false,  // optional - shows loading indicator
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
    // Divider is added automatically between items
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

### 8. Color Overrides — FORBIDDEN outside `lib/theme/`

**NEVER add the following anywhere outside `lib/theme/`:**
- `hoverColor` on `InkWell` / `ListTile` / any widget (except `Colors.transparent` on ListTile with action buttons)
- `splashColor` on any widget
- `overlayColor` on any widget
- `.withValues(alpha: ...)` — color transparency overrides

**Why:** These were used to work around a dark-mode color bug (fixed in commit f938a1860 via `ColorScheme.fromSeed`). Now the theme computes all interaction colors correctly. Adding them manually breaks theme consistency and will break again when themes change.

**If you need to define a custom interaction color or transparency:**
→ Define it in `lib/theme/app_theme_data.dart` or `lib/theme/app_surfaces.dart`, not in feature files.

**Exceptions (the only allowed uses outside `lib/theme/`):**
- `hoverColor: Colors.transparent` on a `ListTile` that contains action buttons in its trailing/leading (prevents double-hover)
- `BoxShadow` colors with `.withValues(alpha: ...)` — shadows require transparency by nature
- Loading overlays / semi-transparent backgrounds that are structural (not interaction feedback)

### 7. Segmented Settings - ONLY `SegmentedSettingsTile`
```dart
import 'package:otzaria/widgets/widgets_exports.dart';

// Setting with 2-4 options
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
    // update BLoC
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
The app uses `locale: Locale("he", "IL")` + `GlobalWidgetsLocalizations.delegate` in `MaterialApp`.
This sets `Directionality.rtl` **globally** for the entire widget tree — every `Text` inherits RTL automatically.

**textDirection rule — Critical:**
- **NEVER add** `textDirection: TextDirection.rtl` to `Text` — it is completely redundant.
- **ADD** `textDirection: TextDirection.ltr` **only** for inherently LTR content:
  - OS file / folder paths
  - Email addresses
  - Version numbers / hash values
  - URLs
  - Technical identifiers (clearly LTR format)
- For parameters like `subtitleDirection` — pass `textDirection` to `Text` **only when the value is LTR**:
  ```dart
  // Correct:
  textDirection: subtitleDirection == TextDirection.ltr ? TextDirection.ltr : null,
  // Wrong — never pass TextDirection.rtl:
  // textDirection: subtitleDirection,  // ❌ when the default is rtl
  ```
- Use `RtlTextField` for all text inputs
- Test UI with Hebrew text before committing

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
/// Returns a list of books by category
///
/// [category] - the category name
/// Returns [Future<List<Book>>] - list of books or error
/// Throws [RepositoryException] if data not found
Future<List<Book>> getBooksByCategory(String category) async {
  // Implementation
}
```

### Code Comments — Minimal & For the First-Time Reader (MANDATORY)

**הכלל: פחות הערות, וקצרות. הוסף הערה רק כשהיא באמת נצרכת.**

- **כמות** - אל תוסיף הרבה הערות. רוב הקוד צריך להסביר את עצמו דרך שמות ברורים.
- **אורך** - הערה נצרכת תהיה קצרה - **מקסימום 2 שורות**.
- **קהל היעד** - כתוב הערה רק למי שקורא את הקוד **בפעם הראשונה**. ההערה מסבירה *למה* הקוד עושה משהו לא מובן מאליו, או מתעדת מלכוד שאם ישנו אותו יחזור באג. זו ההצדקה היחידה להערה.
- **לא רלוונטי** - אסור להערות שמתעדות היסטוריה: "פעם היה כך", "שונה ב-commit X", "הוספנו כי...", "TODO ישן", קוד מבוטל בהערה. למשתמש שקורא עכשיו לא מעניין מה היה - הגיט מתעד את זה.

```dart
// ❌ רע - מתעד היסטוריה, לא רלוונטי לקורא:
// פעם השתמשנו ב-setFullScreen אבל זה איבד WS_VISIBLE אז שינינו

// ✅ טוב - מזהיר ממלכוד שיחזיר באג אם ישונה (קצר):
// setFullScreen על חלון מוסתר מאבד WS_VISIBLE - חובה להציג קודם
```

**אם נתקלת בהערה קיימת שמפרה את ההנחיה משמעותית** (ארוכה מדי, מתעדת היסטוריה, מיותרת) - **תקן/מחק אותה** כחלק מהעבודה על אותו קובץ.

## Testing Strategy

### Before Every Commit (MANDATORY)
```bash
flutter analyze              # Must pass with ZERO errors/warnings
flutter test test/feature/   # Run ONLY tests related to your changes
dart format lib/file.dart    # Format ONLY files you modified
```

> **Tip:** The project uses `dart_pre_commit` as a git pre-commit hook.
> After cloning, run once: `dart run tool/install_git_hooks.dart`.
> From that point, `dart format` and `dart analyze` run automatically on staged files
> before every commit. Tests must still be run manually — they are not part of the hook.

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
4. **Icons** - Only `fluentui_system_icons`. Use `RtlIcon` **only** for icons registered in `lib/widgets/misc/rtl_icon.dart` (`_fluentMirrorMap`, `_materialMirrorMap`, `_flippableIcons`). All other icons: plain `Icon(...)`. Never add manual `Transform` on icons — register in `rtl_icon.dart` instead.
5. **User messages** - Only through `UiSnack`, never direct SnackBar
6. **Dialogs** - Only through `custom_ui_components` (SingleActionDialog, TwoActionsDialog, WarningDialog)
7. **Action buttons** - Only `RecommendedActionButton` or `NeutralActionButton` from `custom_ui_components`
8. **Settings cards** - Only `SettingsCard` from `settings_card.dart`
9. **Color theming** - NEVER use hardcoded colors (Colors.red, Colors.blue, etc.), ALWAYS use `Theme.of(context).colorScheme`
10. **Hover effects** - Remove from ListTile rows with buttons (`hoverColor: Colors.transparent`)
11. **No color overrides outside `lib/theme/`** - NEVER add `hoverColor`, `splashColor`, `overlayColor`, or `.withValues(alpha:...)` in feature files — define them in `lib/theme/` only
11. **textDirection** - NEVER add `textDirection: TextDirection.rtl` (the app's locale sets RTL globally). ONLY add `textDirection: TextDirection.ltr` for inherently LTR content: OS paths, email addresses, version numbers, URLs
12. **Test coverage** - Add/update tests for every code change
13. **Documentation** - Document all public APIs in Hebrew
14. **Cross-platform** - Code must work on all supported platforms
15. **Pre-commit trinity** - `analyze` + `test` + `format` = mandatory
16. **Minimal comments** - Few comments, max 2 lines each, for the first-time reader only (explain *why* / prevent regressions) — never document history. Fix violating comments you encounter

### Common Mistakes to Avoid
- Fixing a bug by adding code instead of finding and removing the root cause
- Patching around a null/error with defensive code without understanding why it occurs
- Asking the user questions that could be answered by reading the code or git history
- Asking multiple separate questions instead of batching all open questions into one message
- Writing a large diff to fix what should be a small bug
- Using `TextField` instead of `RtlTextField`
- Using Material/Cupertino icons instead of FluentUI (unless Material icon is in `_materialMirrorMap` in `rtl_icon.dart`)
- Using `RtlIcon` for icons **not** registered in `lib/widgets/misc/rtl_icon.dart` — check first; if not registered, use plain `Icon(...)`
- Forgetting to use `RtlIcon` for icons that **are** registered in `lib/widgets/misc/rtl_icon.dart`
- Adding `mirrorIcon` parameter to any widget — FORBIDDEN (removed in commit 3b4d357)
- Manual `Transform.scale(scaleX: -1)` or `Transform.flip` on icons — register the icon in `rtl_icon.dart` instead
- Showing messages without `UiSnack`
- Using custom dialogs instead of `custom_ui_components` dialogs
- Using `ElevatedButton`/`TextButton` instead of `RecommendedActionButton`/`NeutralActionButton`
- Using hardcoded colors instead of `Theme.of(context).colorScheme`
- Not removing hover effects from ListTile rows with action buttons
- Adding `hoverColor`, `splashColor`, `overlayColor`, or `.withValues(alpha:...)` outside `lib/theme/` — these belong only in the theme layer
- Adding `textDirection: TextDirection.rtl` to any `Text` widget — the app's locale already sets RTL globally, this is always redundant
- Missing `textDirection: TextDirection.ltr` on LTR content (OS paths, emails, version numbers, URLs)
- Skipping `flutter analyze` before committing
- Running full test suite instead of relevant tests
- Formatting entire project instead of modified files
- Moving to next feature while current code has warnings
- Not testing on multiple platforms
- Hardcoding platform-specific paths
- Creating unnecessary MD files to document changes (CHANGES.md, SUMMARY.md, etc.)
- Adding too many comments, long comments (over 2 lines), or comments that document history ("used to be X", "changed in commit Y") instead of explaining *why* for a first-time reader

---

**Remember: ALWAYS respond in Hebrew!**
