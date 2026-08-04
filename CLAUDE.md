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
- `list_24_regular`

**If you need to flip an icon that is NOT yet registered:**
Add it to the appropriate set/map in `lib/widgets/misc/rtl_icon.dart`, then use `RtlIcon`. Do NOT add manual `Transform.flip`/`Transform.scale` in feature files.

**Never use:**
- Material Icons (unless in `_materialMirrorMap` above)
- Cupertino Icons
- Custom icon fonts
- Random icon packages
- `mirrorIcon` parameter on any widget — **FORBIDDEN**, removed in commit 3b4d357
- Manual `Transform.scale(scaleX: -1, ...)` or `Transform.flip(flipX: true, ...)` around icons — register in `rtl_icon.dart` instead
- Comments explaining why `RtlIcon` or `Icon(...)` was chosen — the decision rule is documented here; do NOT repeat it inline in code

### 2. User Messages - ONLY via `UiSnack`
```dart
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/messages_exports.dart';

UiSnack.show(CommonMessages.savedSuccessfully);
UiSnack.showError(ReportMessages.sendFailed);
UiSnack.show(UiSnack.textCopied);          // Legacy alias → CommonMessages
```

**Message texts are centralized (MANDATORY):** Never pass a hardcoded string literal to `UiSnack`. Every message lives in `lib/core/messages/` — one catalog per domain (`CommonMessages`, `ReportMessages`, `SettingsMessages`, `TextBookMessages`, `ToolsMessages`, `NotesMessages`, `LibraryMessages`, `PluginMessages`, `PdfMessages`). Fixed texts are `static const`; parameterized texts are static functions. Add new messages to the matching catalog (or `CommonMessages` if shared).

**Never use:**
- Hardcoded message strings at `UiSnack` call sites — add to `lib/core/messages/` instead
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

### 5. Action Buttons - ONLY `ActionButton` named constructors
```dart
import 'package:otzaria/widgets/widgets_exports.dart';

// Recommended action button (Primary style)
ActionButton.recommended(
  text: 'שנה מיקום',
  onPressed: () => _changeLocation(),
  isLoading: false,  // optional - shows loading indicator
);

// Neutral/non-recommended action button (Tonal style)
ActionButton.neutral(
  text: 'איפוס',
  onPressed: () => _resetSettings(),
  isLoading: false,  // optional - shows loading indicator
);

// Ghost (transparent, neutral)
ActionButton.ghost(
  text: 'ביטול',
  onPressed: () => _cancel(),
);

// Warning (transparent background, error-color text — for destructive actions)
ActionButton.warning(
  text: 'מחק לצמיתות',
  onPressed: () => _delete(),
);
```

**Button Styling Rules (CRITICAL):**
- **ActionButton.recommended**: FilledButton (primary background, onPrimary text)
- **ActionButton.neutral**: FilledButton.tonal (surfaceContainerHighest background, onSurface text)
- **ActionButton.ghost**: TextButton (transparent, neutral color)
- **ActionButton.warning**: TextButton (transparent, cs.error text — for destructive confirmations)
- **NEVER use hardcoded colors** - always use `Theme.of(context).colorScheme`

**When to use which button:**
- `ActionButton.recommended` - recommended actions (change settings, choose location, update, add)
- `ActionButton.neutral` - neutral or dangerous actions (reset, delete, remove, stop)
- `ActionButton.ghost` - secondary inline text actions (cancel, close, skip)
- `ActionButton.warning` - destructive confirmation (delete, clear, overwrite — matches WarningDialog's confirm button)

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

### 9. Settings Screen Text — ALWAYS Through `settingsText`

The settings screen has an English mode (`lib/settings/l10n/`). **Every new user-visible string under `lib/settings/` must be wrapped** — an unwrapped string silently stays Hebrew when the user picks English.

```dart
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

Text(context.settingsText('גודל גופן הספר'))

// Placeholders — never string interpolation, so the translation can reorder them:
context.settingsText('יש כרגע {count} דיווחים שמורים בתור', args: {'count': pendingCount})

// Identical Hebrew with different translations — separate with a context:
context.settingsText('ספריה', context: 'titleBar')   // → "Library"
context.settingsText('ספריה')                        // → "Seforim Library"
```

**The Hebrew source string IS the translation key.** Never invent a key like `'settings.font.size'`: a maintainer looking for a screen greps the Hebrew text they see on it, and that has to keep working. The English text lives only in `lib/settings/l10n/settings_en.arb`.

**After adding or changing a string, regenerate the catalog:**
```bash
dart run tool/generate_settings_l10n.dart
```
It reads the ARB and writes the `const` map in `lib/settings/l10n/settings_catalogs.g.dart`. It also runs on `flutter run` / `flutter build` / `flutter test` via the build hook — but **not on hot reload**, so an ARB edit needs a restart to appear.

The generator validates the ARB itself (duplicate keys, placeholder mismatch). What catches a *missing* translation is `test/settings/l10n/settings_l10n_test.dart`, which scans the code for `settingsText` calls and fails on any key absent from the ARB — plus the reverse, an ARB entry no longer used. Run it after touching any settings string:
```bash
flutter test test/settings/l10n/
```

**Never do:**
- A bare string literal on a settings widget's `title` / `subtitle` / `label` / `tooltip` / dialog text
- String interpolation inside the key (`'שמור ${count} ספרים'`) — use `args:` instead
- A non-Hebrew invented key
- Editing `settings_catalogs.g.dart` by hand — it is generated, and your edit is lost on the next build
- `textDirection` or `Directionality` to "fix" the English mode — the app stays RTL; only the settings screen switches locally

**Two traps that make a string render Hebrew even though it looks wrapped:**

1. **A string reaching `settingsText` through a variable is invisible to the scanner.** It reads literal arguments only, so `context.settingsText(item.label)` passes the coverage test with no translation existing. When the text arrives via a variable, field, or table, add an explicit case to `test/settings/l10n/settings_variable_labels_test.dart`.

2. **A dialog builds in the Navigator's Overlay, outside the settings widget tree**, so it inherits neither the language nor the direction. Open it through `settingsDialogBuilder`:
   ```dart
   showDialog(context: context, builder: settingsDialogBuilder(context, (_) => const MyDialog()));
   ```

Strings outside `lib/settings/` are Hebrew-only by design — do **not** wrap them. Two areas are the exception and **do** go through the same catalog:

- **`lib/navigation/`** — the fixed navigation rail and the title-bar screen names, because the settings screen is reached from them.
- **`lib/tour/`** — the guided tour and the live tips. **Every new tour step title/body and every live-tip title/description needs an ARB entry**, same as a settings string; see `docs/guided_tour_developer_guide.md`. Two rules specific to the tour: a step's `body` must stay a plain string literal (a variable value goes in as a placeholder — a keyboard shortcut via `shortcut:` filling `{shortcut}`), and coverage is guarded by `test/settings/l10n/settings_variable_labels_test.dart`, which builds the steps for real, so a step with no translation fails there rather than rendering Hebrew.

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

### Test File Map — Feature → Test File

**Text Book Viewer**
| Area | Test File |
|------|-----------|
| Screen actions (overflow, layout) | `test/text_book/view/text_book_screen_actions_test.dart` |
| Search controller sync | `test/text_book/text_book_search_query_sync_test.dart` |
| Search screen | `test/text_book/view/text_book_search_screen_test.dart` |
| TOC navigator UI | `test/text_book/view/toc_navigator_screen_test.dart` |
| TOC navigator internals | `test/text_book/view/toc_navigator_internals_test.dart` |
| Combined view helpers (shouldShow…) | `test/text_book/view/combined_view/combined_book_screen_test.dart` |
| TabbedCommentaryPanel tab switching / onTabChanged | `test/text_book/view/tabbed_commentary_panel_test.dart` |
| Page shape commentary selection | `test/text_book/view/page_shape_commentary_selection_test.dart` |
| חלונית הצד של צורת הדף (3 לשוניות) | `test/text_book/view/page_shape/page_shape_sidebar_tabs_test.dart` |
| תפריט הקשר בצורת הדף (מפרשים / קטע היעד) | `test/text_book/view/page_shape/simple_text_viewer_context_menu_test.dart` |
| תת-תפריט "מפרשים" המשותף + מדיניות הצגה | `test/text_book/utils/commentators_context_menu_test.dart` |
| SimpleTextViewer | `test/text_book/view/page_shape/simple_text_viewer_test.dart` |
| Selected text copy/restore | `test/text_book/view/selection/selected_text_copy_test.dart`, `…selected_text_restore_test.dart` |
| SelectionSyncController | `test/text_book/view/selection/selection_sync_controller_test.dart` |
| Commentary open-filter request | `test/text_book/view/commentary_list_base_open_filter_test.dart` |
| Commentary search focus | `test/text_book/view/commentary_search_focus_test.dart` |
| Commentary grouping | `test/text_book/commentary_grouping_test.dart` |
| Book source dialog | `test/text_book/view/book_source_dialog_test.dart` |
| Error report dialog | `test/text_book/view/error_report_dialog_test.dart` |

**Text Book BLoC**
| Area | Test File |
|------|-----------|
| BLoC state equality | `test/text_book/bloc/text_book_state_test.dart` |
| Background content loading | `test/text_book/bloc/background_full_content_loading_test.dart` |
| Continuous reading mode | `test/text_book/bloc/continuous_reading_mode_test.dart` |
| Selected link types persistence | `test/text_book/bloc/selected_link_types_persistence_test.dart` |
| visibleIndices throttling (scroll perf) | `test/text_book/bloc/visible_indices_throttle_test.dart` |

**Data / Database**
| Area | Test File |
|------|-----------|
| DatabaseLibraryProvider (links, alt-toc, isolate regressions) | `test/data_providers/database_library_provider_test.dart` |
| DatabaseLibraryProvider has-book | `test/data_providers/database_library_provider_has_book_test.dart` |
| UserBooksDB | `test/data_providers/user_books_database_holder_test.dart` |
| FileSystemLibraryProvider | `test/data_providers/file_system_library_provider_test.dart` |
| ExternalCatalogMapper | `test/data_providers/external_catalog_mapper_test.dart` |
| TantivyDataProvider (search index) | `test/data/data_providers/tantivy_data_provider_test.dart` |
| External books scanner | `test/data/data_providers/scan_external_books_test.dart` |
| Library book search (fuzzy + acronyms) | `test/data/repository/book_search_fuzzy_match_test.dart` |

**Search**
| Area | Test File |
|------|-----------|
| Find-match utils | `test/search/find_match_utils_test.dart` |
| Catalogue order helper | `test/search/search_catalogue_order_helper_test.dart` |
| Enhanced search field | `test/search/enhanced_search_field_test.dart` |
| Book facet | `test/search/book_facet_test.dart` |
| Facet helper | `test/search/facet_helper_test.dart` |
| Search BLoC facet counts | `test/search/search_bloc_facet_counts_test.dart` |
| Search scope preferences | `test/search/search_scope_preferences_test.dart` |
| Gematria search | `test/tools/gematria/gematria_search_test.dart` |

**Personal Notes**
| Area | Test File |
|------|-----------|
| Notes screen | `test/personal_notes/personal_notes_screen_test.dart` |
| Note tile | `test/personal_notes/widgets/note_tile_test.dart` |
| Note editor | `test/personal_notes/personal_note_editor_test.dart` |
| Note draft service | `test/personal_notes/personal_note_draft_service_test.dart` |
| Note content view | `test/personal_notes/personal_note_content_view_test.dart` |
| Notes export | `test/personal_notes/personal_notes_export_test.dart` |

**Settings**
| Area | Test File |
|------|-----------|
| Nikud display service | `test/settings/nikud_display_service_test.dart` |
| Settings repository | `test/settings/settings_repository_test.dart` |
| Settings screen controller | `test/settings/settings_screen_controller_test.dart` |
| Bookmark model | `test/settings/history/bookmark_model_test.dart` |
| Custom folders BLoC | `test/settings/services/custom_folders/custom_folders_bloc_test.dart` |
| Backup service (roundtrip, plugins, auto-backup) | `test/settings/services/backup_service_test.dart` |
| Backup store (blobs, dedup, GC) + maintenance helpers | `test/unit/settings/backup/backup_store_test.dart` |
| Backup rotation (GFS) | `test/unit/settings/backup/backup_rotation_test.dart` |
| Backup archive merge rules | `test/unit/settings/backup/backup_merge_test.dart` |
| SegmentedSettingsTile | `test/settings/widgets/segmented_settings_tile_test.dart` |
| SwitchSettingsTile | `test/settings/widgets/switch_settings_tile_test.dart` |

**Widgets (shared)**
| Area | Test File |
|------|-----------|
| App menu | `test/widgets/app_menu_test.dart` |
| App top bar | `test/widgets/app_top_bar_test.dart` |
| Context overlay panel | `test/widgets/context_overlay_panel_test.dart` |
| Context menu (incl. hover preview + pinning) | `test/widgets/app_context_menu_test.dart` |
| Link preview panel (placement, pin, scroll anchor) | `test/widgets/link_preview_overlay_test.dart` |
| Dual adaptive reader pane | `test/widgets/dual_adaptive_reader_pane_test.dart` |
| Nav rail item | `test/widgets/nav_rail_item_test.dart` |
| Reader side panel shell | `test/widgets/reader_side_panel_shell_test.dart` |
| Responsive action bar | `test/widgets/responsive_action_bar_test.dart` |
| Scrollable list scrollbar | `test/widgets/scrollable_positioned_list_scrollbar_test.dart` |
| Smooth mouse-wheel scrolling | `test/widgets/smooth_wheel_scroll_test.dart` |
| Smart text render settings | `test/widgets/smart_text/render_settings_test.dart` |
| Smart text ↔ plugin section sync gate | `test/widgets/smart_text/smart_text_section_sync_gate_test.dart` |
| Work/indexing status overlays | `test/widgets/work_status_overlay_test.dart`, `…indexing_status_overlay_test.dart` |
| App dropdown/search menu | `test/widgets/app_dropdown_field_test.dart`, `…app_search_menu_test.dart` |
| Search pane base | `test/widgets/search_pane_base_test.dart` |

**Navigation / Startup**
| Area | Test File |
|------|-----------|
| Navigation BLoC | `test/navigation/navigation_bloc_test.dart` |
| Startup guard / auto-reindex | `test/navigation/startup_work_gate_test.dart`, `…startup_auto_reindex_test.dart`, `…new_books_indexing_guard_test.dart` |

**Other Features**
| Area | Test File |
|------|-----------|
| Bookmarks BLoC | `test/bookmarks/bookmark_bloc_test.dart` |
| Workspaces BLoC | `test/workspaces/bloc/workspace_bloc_test.dart` |
| Windows installer scripts (`.iss` invariants) | `test/installer/installer_scripts_test.dart` |
| App paths / install-mode detection | `test/core/app_paths_test.dart` |
| Library browser | `test/library/view/library_browser_preview_width_test.dart`, `…grid_items_test.dart`, `…library_browser_flat_tree_test.dart` |
| Empty library screen | `test/empty_library/empty_library_screen_test.dart` |
| PDF isolate / rasterizer | `test/printing/pdf_isolate_test.dart`, `…pdf_text_rasterizer_test.dart` |
| PDF in-book search highlight pattern | `test/pdf_book/pdf_search_highlight_pattern_test.dart` |
| Printing models | `test/printing/print_content_models_test.dart` |
| File sync / background sync | `test/migration/sync/file_sync_service_prune_test.dart`, `…background_db_sync_worker_test.dart`, `…background_sync_initializer_test.dart` |
| DB migration / generator | `test/migration/generator_create_and_process_book_test.dart`, `test/migration/dao/daos/database_locked_test.dart` |
| Indexing repository | `test/indexing/repository/indexing_repository_test.dart` |
| External catalog | `test/external_catalog/external_catalog_repository_test.dart`, `…settings_helper_test.dart` |
| Plugins | `test/plugins/utils/reader_location_resolver_test.dart`, `…plugin_store_link_parser_test.dart`, `…plugin_bridge_adapter_test.dart` |
| Plugin highlights / reader section tracking | `test/plugins/services/plugin_highlight_registry_test.dart`, `…reader_section_content_tracker_test.dart`, `…reader_section_sync_gate_test.dart` |
| Shamor Zachor | `test/shamor_zachor/shamor_zachor_test.dart` (+ 4 more in that dir) |
| Dictionary lookup | `test/tools/dictionary/dictionary_lookup_repository_test.dart` |
| Laaz Rashi commentary line-lookup | `test/tools/dictionary/laaz_rashi_line_lookup_test.dart` |
| Laaz Rashi commentary sub-block widget | `test/tools/dictionary/laaz_commentary_subblock_test.dart` |
| Laaz Rashi commentary wiring (surfaces) | `test/tools/dictionary/laaz_commentary_wiring_test.dart` |
| Commentary reverse links | `test/text_book/commentary_reverse_links_test.dart` |
| Inline links | `test/models/inline_links_test.dart` |
| Dialog navigation | `test/widgets/dialogs/dialog_navigation_test.dart` |
| Focus restore | `test/core/focus_restore_test.dart` |
| Models (books, links) | `test/models/books_test.dart`, `…links_test.dart`, `…phone_report_data_test.dart` |
| Link types (נרמול, סוג קנוני, תוויות) | `test/models/link_types_test.dart` |
| Utils (page map builder, page converter, TOC parser) | `test/utils/page_map_builder_test.dart`, `…page_converter_test.dart`, `…toc_parser_test.dart` |
| Utils (link processing) | `test/text_book/utils/link_processing_test.dart` |
| Hebrew text utils (migration) | `test/migration/hebrew_text_utils_test.dart` |
| Text book searcher (in-book search) | `test/text_book/models/text_book_searcher_test.dart` |
| Note text utils | `test/personal_notes/note_text_utils_test.dart` |
| Shortcut validator | `test/shortcuts/shortcut_validator_test.dart` |
| Core (activation queue/channel, error log) | `test/core/` |
| Error logging | `test/core/main_error_logging_test.dart`, `test/services/direct_error_report_service_test.dart` |

**Calendar (`lib/tools/calendar/`)**
| Area | Test File |
|------|-----------|
| Cubit (אירועים, פלאגינים, התראות) | `test/tools/calendar/utils/calendar_cubit_test.dart` |
| סדר אירועים (לפי שעה) — cubit + משווים | `test/tools/calendar/utils/calendar_event_sorting_test.dart` |
| סדר אירועים בתצוגה (פאנל + תא היום) | `test/tools/calendar/widgets/calendar_events_order_test.dart` |
| זמני היום / אזורי זמן | `test/tools/calendar/utils/calendar_daily_times_test.dart`, `…calendar_timezone_test.dart` |
| כרטיסי זמנים (composite) ורישום הזמנים | `test/tools/calendar/widgets/calendar_composite_entries_test.dart` |
| עזרי זמנים / מולד | `test/tools/calendar/helpers/zmanim_helpers_test.dart`, `…molad_helpers_test.dart` |
| דיאלוגים | `test/tools/calendar/dialogs/calendar_dialogs_test.dart` |
| תא היום (JewishCalendar משותף) | `test/tools/calendar/widgets/day_cell_shared_calendar_test.dart` |
| פוקוס וניווט מקלדת | `test/tools/calendar/widgets/calendar_widget_focus_test.dart`, `…calendar_top_bar_focus_test.dart` |
| החלקה בין חודשים | `test/tools/calendar/widgets/calendar_main_panel_swipe_test.dart` |
| פריסה רספונסיבית | `test/tools/calendar/calendar_screen_responsive_test.dart` |

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
7. **Action buttons** - Only `ActionButton.recommended` / `.neutral` / `.ghost` from `widgets_exports.dart`
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
17. **Settings screen text** - Every user-visible string under `lib/settings/` goes through `context.settingsText('<Hebrew>')`, with the Hebrew as the key and the English in `settings_en.arb`; run `dart run tool/generate_settings_l10n.dart` after any change
18. **Guided tour text** - Same rule for `lib/tour/`: every step title/body and live-tip title/description needs a `settings_en.arb` entry, and a step's `body` stays a literal (variables go in as placeholders)

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
- Adding inline comments that explain why `RtlIcon` or `Icon(...)` was chosen — the decision rule lives in CLAUDE.md, not in code
- Showing messages without `UiSnack`
- Using custom dialogs instead of `custom_ui_components` dialogs
- Using `ElevatedButton`/`TextButton` directly instead of `ActionButton.recommended`/`.neutral`/`.ghost`
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
- Adding a bare Hebrew string to a settings widget instead of `context.settingsText(...)` — it stays Hebrew in English mode
- Using string interpolation inside a `settingsText` key instead of `args:`
- Editing `settings_catalogs.g.dart` by hand instead of `settings_en.arb` + the generator
- Opening a dialog from settings without `settingsDialogBuilder` — it inherits neither language nor direction
- Passing a variable to `settingsText` without a case in `settings_variable_labels_test.dart` — the validator only sees literals
- Adding too many comments, long comments (over 2 lines), or comments that document history ("used to be X", "changed in commit Y") instead of explaining *why* for a first-time reader

---

**Remember: ALWAYS respond in Hebrew!**
