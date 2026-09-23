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

### Proving a bug fix

Reproduce the reported behavior when practical. For a regression, prefer a focused test that fails before the fix and passes afterward, using the reporter's relevant conditions. Inspect all callers before changing shared code; preserve their behavior. Do not weaken an existing test just to make the change pass. For visible UI bugs, compare before/after behavior when practical. Report exactly which checks passed, failed or were not run.

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

## Scope and artifacts

Follow the user's task scope. Do not create Markdown files for plans, progress logs, change summaries or test results by default; report those in the conversation or PR. Create or update a Markdown file when the user requests it, when it is a durable reference needed by this repository, or when an existing repository process explicitly requires it. Prefer updating an existing document.

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


## Startup Path (MANDATORY)

**The rule: nothing runs during startup unless it must run before the first frame.**

Every `await` added to `main()` is paid by every user on every launch, forever. Startup
regressions are also the hardest bugs in this app to diagnose: they reproduce only on the
reporter's machine, and the blocking call is usually invisible from Dart. Issues #343, #989 and
#1192 were three instances of the same mistake.

### Why Windows startup is different

On Windows the Dart **UI isolate runs on the platform thread**. A synchronous native call — COM /
WinRT, a registry write, `Process.run`, a plugin's `initialize()` — blocks that thread, and with
it **every Dart frame and every Dart timer**. In #1192 a notification-plugin init that costs ~50ms
on a dev machine blocked for **30 seconds** inside one COM call on a reporter's machine.

Two consequences that are easy to get wrong:

- **A `Future.timeout` does not protect you.** The timer that would fire it is queued on the same
  blocked thread. You cannot defend against synchronous native work with a Dart timeout — you can
  only avoid making the call.
- **A slow machine is not a slower version of yours.** Filtering agents, antivirus, managed
  profiles and roaming registry hives change the *shape* of the cost, not just its size: process
  spawn becomes ~1s each (#989), a registry subtree becomes unwritable, an OS service stops
  answering. Never conclude "it's fast" from your own box.

### Before adding anything to `main()` / `AppBootstrap`

Answer all three, in this order:

| Question | If the answer is… |
|---|---|
| Is it required to paint the first frame? | No → run it after reveal (below) |
| Do the call sites already initialize on demand? | Yes → **delete it** — that is the whole fix |
| Can it be skipped based on stored state? | Yes → gate on that state and run only when needed |

#1192 answered all three: the notification plugin was initialized eagerly, every call site already
did `if (!isInitialized) await init()`, and the one genuine need — restoring already-scheduled
alerts — applies only when alerts are actually stored. The fix deleted the call rather than
speeding it up.

### Running work after the window is revealed

Deferred work lives in a `_runDeferredX()` function in `main.dart`, launched with `unawaited(...)`,
and waits for the reveal with a timeout so it still runs if the reveal never lands:

```dart
Future<void> _runDeferredThing() async {
  // פר-תהליך: חלון משני היה מריץ את זה שוב על אותם משאבים.
  if (WindowRole.isSecondary) return;
  try {
    await _mainWindowRevealedCompleter.future.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    // ממשיכים בכל זאת — אחרת המשימה לא תרוץ כלל.
  }
  try {
    await doTheThing();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Thing', error, stackTrace);
  }
}
```

Three parts, all mandatory:

1. **`WindowRole.isSecondary` guard** for anything per-process or per-machine (registry, system
   notifications, update checks, error-report flush). Without it every extra window repeats it.
2. **Reveal gate with a timeout** — never an unguarded `await` on the completer.
   **Exception:** a step that makes a synchronous native call (e.g. `sentry_init` in
   `_initializeSentry`) awaits the reveal with **no** timeout. Running it before reveal is the
   #1192 block itself, and it would hit exactly the machines whose reveal is slow.
3. **Non-fatal failure** — a startup step must never abort the boot. It logs through
   `_logNonFatalInitializationError` and returns.

### Forbidden on the startup path

| Never | Instead |
|---|---|
| Synchronous COM / WinRT / FFI on the main isolate | Defer past reveal, or don't call it |
| `Process.run` in a loop (`reg.exe`, `which`, …) | Use the direct API (#989: 10 spawns blew every timeout) |
| A network call without a timeout | Explicit timeout on every request (#343) |
| Heavy CPU on the main isolate (parsing, scanning, hashing) | `compute` / `Isolate.run` |
| Sync file I/O over a directory tree | Async, off the reveal path, memoized |
| A failure that propagates out of an init step | `_logNonFatalInitializationError` |

**Cosmetic extras are best-effort, and must say so.** A step that only improves polish — a shell
icon, an Office trusted-protocol key, a cache warm-up — swallows its own failures per item, so one
denied write does not abort the rest and does not reach the error log. Registering a real handler
is not cosmetic; marking it trusted is.

### Instrumentation

`StartupTimeline` (`lib/core/startup_timeline.dart`) records phases and marks and writes a
`=== Slow startup` record to `errors.txt` only when reveal exceeded its threshold. It carries a
**deliberately small permanent skeleton** — the bootstrap phases, `reveal:*`, `mainScreenInit`,
`bootstrapDone`/`bootstrapReady` and the stall detector.

- Wrap a new heavy startup step in `StartupTimeline.instance.phase('name', ...)` — that is the
  skeleton growing correctly.
- **Never put a mark inside `build()` or a per-frame callback.** Marks added while chasing a
  specific report are temporary: remove them in the same PR that fixes the cause.
- A `stall:<ms>` mark means the isolate stopped answering — the blocker is synchronous, and if no
  Dart mark brackets it, it is **native**.

When Dart-side marks show nothing, use the native stall detector in
`windows/runner/startup_watchdog.cpp`. It suspends the main thread, unwinds it without dbghelp, and
appends `=== Startup stall` with module+RVA frames to `errors.txt`. It stops itself at reveal and
is silent on a healthy launch. That is how #1192 was found after three rounds of Dart instrumentation
missed it.

## UI rules

Read the relevant section of `docs/agent_ui_reference.md` before changing UI; do not load it for unrelated tasks.

- Icons: prefer `otzaria_icons` for its supported cases; use Fluent for generic chrome and the documented exceptions. `OtzariaIcons` always uses plain `Icon`; registered directional Fluent icons use `RtlIcon`. Never use Material/Cupertino icons or manually flip icons.
- Messages use centralized `UiSnack` catalogs; text inputs use `RtlTextField`; dialogs, action buttons and settings cards use the shared components.
- Use theme colors and shared interaction styling. Do not add color overrides in feature files.
- New settings, navigation and tour strings use `context.settingsText` and `settings_en.arb`; regenerate the catalog and run `flutter test test/settings/l10n/`.
- Navigation panels use `NavSidePanel` and its shared search/tree components. Middle-click autoscroll is global; use `AutoScrollBarrier` only where middle-click has another action.

## Code Guidelines

### RTL Support (Critical!)
The app uses `locale: Locale("he", "IL")` + `GlobalWidgetsLocalizations.delegate` in `MaterialApp`.
This sets `Directionality.rtl` **globally** for the entire widget tree — every `Text` inherits RTL automatically.

**textDirection rule — Critical:**
- **NEVER add** `textDirection: TextDirection.rtl` to `Text` — it is completely redundant.
- **The rule applies to `Text` only.** Every one of the 19 such calls in `lib/` is required, and
  removing them breaks the app:
  - **`TextPainter`** (11) — it has no `BuildContext` and inherits nothing. `layout()` throws
    `TextPainter.textDirection must be set to a non-null value`. Guarded by
    `test/widgets/text_painter_direction_test.dart`.
  - **`Directionality`** (3) — pinning a subtree back to RTL is the mechanism itself
    (`ContentDirectionality`, the PDF export, a colour swatch grid whose order must not flip).
  - **A widget that may render under an LTR interface language** (4) — anything reached from
    `lib/settings/`, where `ChromeDirectionality` applies the interface language. A Hebrew
    quotation there needs the explicit `rtl`, or it flips when the settings are in English.
  - **A `MaterialApp` built without a `locale`** (1) — the startup-failure fallback in
    `main.dart`, which has no localization delegates and therefore defaults to LTR.
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

### Choosing tests

Run the tests relevant to the change. Start with `rg --files test | rg '<feature|symbol>'`; consult `docs/agent_test_map.md` when the matching suite is unclear. Read only the relevant section. Do not load the full map for every task.

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

### Windows `search_engine_cargokit` build failure

If MSB8066 hides a `PathExistsException` while copying `search_engine.dll`, inspect `flutter build windows --debug -v`: a process may hold the destination DLL open (often an orphaned `flutter_tester.exe`). Identify the holder before stopping it; a running app's DLL under `runner/Debug` is unrelated. Tests load a separate copy from `build/test_engine/` via `test/support/search_engine_test_init.dart`; do not point them back to the plugin build output.

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
