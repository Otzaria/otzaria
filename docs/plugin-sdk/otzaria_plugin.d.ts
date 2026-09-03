/**
 * Otzaria Plugin SDK — TypeScript Definitions
 * Version: 1.1.0
 *
 * Provides full type-safety when writing Otzaria plugins in TypeScript.
 *
 * Usage:
 *   Add to tsconfig.json: "include": ["otzaria_plugin.d.ts"]
 *   Or: /// <reference path="./otzaria_plugin.d.ts" />
 *
 * The `Otzaria` global is injected automatically by the host.
 * You do NOT need to import or load any script.
 *
 * ---------------------------------------------------------------------------
 * HTML Layout Requirements
 * ---------------------------------------------------------------------------
 *
 * SCROLLING
 *   The plugin runs inside a WebView2 (Windows) / WKWebView (iOS/macOS) /
 *   WebView (Android/Linux). Scrolling is NOT automatic — you must explicitly
 *   allow overflow on the root elements, otherwise the page will be clipped
 *   with no scrollbar and no mouse-wheel response:
 *
 *     html, body {
 *       height: 100%;
 *       overflow-y: auto;   ← required for vertical scroll
 *       overflow-x: hidden; ← or auto, depending on your layout
 *     }
 *
 *   If you use a custom scroll container (e.g. a div that fills the viewport),
 *   apply overflow-y: auto / scroll to that container instead of body.
 *   Avoid `overflow: hidden` on any ancestor of scrollable content.
 *
 * TAB VISIBILITY (manifest: contributes.toolTab.defaultPinned)
 *   Set `defaultPinned: true` in your manifest if you want the plugin tab to
 *   appear automatically in the toolbar after installation.
 *   If `defaultPinned: false`, the user must manually pin the plugin from the
 *   plugin side panel (🧩 button) before it appears as a tab.
 *
 * RTL SUPPORT
 *   Add `dir="rtl"` to the <html> element for Hebrew / Arabic content:
 *     <html dir="rtl" lang="he">
 */

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

/** Response envelope returned by non-streaming `Otzaria.call()` invocations. */
export interface OtzariaResponse<T = unknown> {
  success: boolean;
  data: T | null;
  error: ApiError | null;
}

export interface ColorScheme {
  // ── שדות יסוד (SDK 1.0.0) — תמיד מוחזרים ──────────────────────────────
  primary: string;
  onPrimary: string;
  secondary: string;
  onSecondary: string;
  surface: string;
  onSurface: string;
  surfaceContainerHighest: string;
  error: string;
  onError: string;
  outline: string;

  // ── תפקידי צבע נוספים (נוספו ב-SDK 1.1.0) ─────────────────────────────
  // אופציונליים כדי לשמור תאימות לאחור: תוסף שרץ על גרסת אוצריא ישנה (1.0)
  // לא יקבל אותם. כשהם קיימים — מוחזרים יחד עם שדות היסוד מ-`app.getTheme`.
  primaryContainer?: string;
  onPrimaryContainer?: string;
  /** רקע כפתור ניווט פעיל בסרגל הצד (ה-pill) */
  secondaryContainer?: string;
  /** אייקון/טקסט מעל secondaryContainer */
  onSecondaryContainer?: string;
  tertiary?: string;
  onTertiary?: string;
  tertiaryContainer?: string;
  onTertiaryContainer?: string;
  onSurfaceVariant?: string;
  surfaceContainerLowest?: string;
  surfaceContainerLow?: string;
  surfaceContainer?: string;
  /** רקע הסרגל העליון (AppTopBar) במסכי הספרים */
  surfaceContainerHigh?: string;
  errorContainer?: string;
  onErrorContainer?: string;
  outlineVariant?: string;
  inverseSurface?: string;
  onInverseSurface?: string;
  inversePrimary?: string;
  shadow?: string;
  scrim?: string;
  surfaceTint?: string;
}

export interface Typography {
  /** גופן הקריאה — לטקסט הספר/המסמך בלבד. אסור להחיל על הממשק. */
  fontFamily: string;
  fontSize: number;
  lineHeight: number;
  commentatorsFontFamily: string;
  commentatorsFontSize: number;
  /** גופן הממשק — כפתורים, תפריטים, שדות. נשאר חד בגדלים קטנים.
   *  קיים מ-0.9.97; במארח ישן חסר — שמרו fallback ב-CSS. */
  uiFontFamily?: string;
}

export interface ThemePayload {
  mode: 'light' | 'dark';
  colorScheme: ColorScheme;
  typography: Typography;
}

/** Delivered via `plugin.boot` exactly once, before any user interaction. */
export interface BootPayload {
  plugin: { id: string; version: string };
  app: {
    version: string;
    platform: 'windows' | 'linux' | 'macos' | 'android' | 'ios' | string;
    /** Full locale tag, e.g. `'he-IL'` or `'en'`. */
    locale: string;
    /** Language code only, e.g. `'he'` / `'en'` — mirrors `app.getLocale`. */
    language: string;
    textDirection: 'ltr' | 'rtl';
    /** `true` when the plugin was loaded as a development plugin
     *  (`sourceType=development`); always `false` for a packaged plugin. */
    devMode: boolean;
    /** `'background'` for a silent background engine (no plugin page),
     *  `'foreground'` for a visible tab. */
    runMode: 'background' | 'foreground';
  };
  theme: ThemePayload;
  /** Connectivity as known at boot, without ever blocking on the network.
   *  `hasNetwork`/`isOnline` are `null` when the check has not resolved yet
   *  (first plugin opened in this run) — call `app.getConnectivity()` to await
   *  the real answer. Start online UI hidden and reveal it on `isOnline === true`
   *  so it never flashes for users without a connection. */
  connectivity: ConnectivityStatus;
  /** Currently granted permissions at boot time.
   *  For a fresh runtime snapshot, call `app.getGrantedPermissions()` or
   *  listen to `plugin.permissions_changed`. */
  permissions: string[];
}

/** Result of `app.getConnectivity`, and the `connectivity` field of `plugin.boot`. */
export interface ConnectivityStatus {
  /** The user turned on "no internet access" in Otzaria's settings.
   *  No network check runs at all in this mode. */
  isOfflineMode: boolean;
  /** A connection was found. `null` only in `plugin.boot`, meaning "not resolved yet". */
  hasNetwork: boolean | null;
  /** `!isOfflineMode && hasNetwork` — the only flag most plugins need.
   *  `null` only in `plugin.boot`, meaning "not resolved yet". */
  isOnline: boolean | null;
}

export interface PermissionSnapshot {
  permissions: string[];
}

/** זהות הפורמט של ספר. עבור ספר-מסמך זו הסיומת הקנונית עצמה, כך שפורמט
 *  חדש מקבל זהות יציבה; טקסט ו-Markdown נשארים `'text'`. */
export type BookType =
  | 'text'
  | 'pdf'
  | 'external'
  | 'epub'
  | 'docx'
  | 'docm'
  | 'dotx'
  | 'dotm'
  | 'doc'
  | 'dot'
  | 'wbk'
  | 'xml'
  | 'rtf'
  | 'odt';

export interface BookMeta {
  id?: number | null;
  bookId: string;
  /**
   * מזהה ספר יציב, חוצה-ספקים (`id:<n>` / `uid:<n>` / `ext:<...>`). יציב בין
   * עדכוני ספרייה והעברת ספרייה ושורד שינויי כותרת — עדיף על `bookId` (כותרת),
   * שאינו מובטח ייחודי או יציב. מומלץ לתוסף לאחסן אותו במקום כותרת, עם fallback
   * חינני לכותרת האחרונה שנראתה למקרה קצה של ייתום.
   */
  bookUid?: string;
  title: string;
  type?: BookType | null;
  source?: 'library' | 'user' | 'external' | null;
  topics?: string[];
  categoryPath?: string | null;
  external?: { provider: 'hebrewbooks' | 'otzar'; id: number | string };
}

export interface SearchResult {
  /** `'text'` for a text book, `'pdf'` for a PDF book. */
  type: 'text' | 'pdf';
  book: string;
  text: string;
  index: number;
}

/**
 * זהות ספר קנונית. בקלט די באחד מ-`bookUid`/`id`/`bookId`.
 * `bookUid` (המזהה היציב) פותר את הספר ישירות וחד-משמעית ומתעלם משאר השדות;
 * בהיעדרו, שדות שנשלחים יחד (`id`+`bookId`+`type`) חייבים להתאים לאותו ספר.
 */
export interface BookIdentity {
  /** מזהה יציב מומלץ; ראה `BookMeta.bookUid`. פותר ישירות, מתעלם משאר השדות. */
  bookUid?: string;
  id?: number | null;
  bookId?: string;
  type?: BookType | null;
  source?: 'library' | 'user' | 'external' | null;
  external?: { provider: 'hebrewbooks' | 'otzar'; id: number | string };
}

export type SearchMode = 'exact' | 'advanced' | 'fuzzy';
export type SearchOrder = 'relevance' | 'catalogue' | 'generation';
export type SearchProximityScope =
  | 'wordDistance'
  | 'sameParagraph'
  | 'sameSection';
export type SearchGrouping = 'none' | 'sameSection' | 'identicalText';
export type SearchWordMatchMode = 'all' | 'anyWord' | 'mostWords' | 'atLeast';

/** פרמטרי `search.query` — כל מה שמסך החיפוש של אוצריא שולח למנוע. */
export interface SearchQueryParams {
  query: string;
  negativeQuery?: string;
  mode?: SearchMode;
  order?: SearchOrder;
  /** נחתך ל-500; יחד עם offset אסור לעבור את חלון 10,000 התוצאות. */
  limit?: number;
  /** יחד עם limit הממשי אסור לעבור את חלון 10,000 התוצאות. */
  offset?: number;
  /** במצב fuzzy הטווח הנתמך הוא 0–2. */
  distance?: number;
  proximityScope?: SearchProximityScope;
  grouping?: SearchGrouping;
  wordMatchMode?: SearchWordMatchMode;
  /** חוקי רק ב-advanced יחד עם wordMatchMode: 'atLeast'. */
  wordMatchCount?: number;
  /** אפשרויות מילה שחלות על כל מילות השאילתה. */
  options?: Record<string, boolean>;
  /** אפשרויות פר-מילה במפתח `"{מילה}_{אינדקס}"`; גובר על `options`. */
  wordOptions?: Record<string, Record<string, boolean>>;
  alternativeWords?: Record<string, string[]>;
  customSpacing?: Record<string, string>;
  negativeDistance?: number;
  negativeProximityScope?: SearchProximityScope;
  negativeOptions?: Record<string, boolean>;
  negativeWordOptions?: Record<string, Record<string, boolean>>;
  negativeAlternativeWords?: Record<string, string[]>;
  negativeCustomSpacing?: Record<string, string>;
  categories?: string[];
  books?: BookIdentity[];
  authors?: string[];
  eras?: string[];
  baseBooksOnly?: boolean;
  facets?: string[];
  includeBookCounts?: boolean;
}

export interface SearchQueryHit extends BookIdentity {
  book: string;
  categoryPath?: string | null;
  reference: string;
  text: string;
  index: number;
  mergedCount: number;
  merged?: Array<
    BookIdentity & {
      book: string;
      categoryPath?: string | null;
      reference: string;
      index: number;
    }
  >;
}

export interface SearchQueryChunk {
  /** מספר ה-chunk, החל מ-0. */
  sequence: number;
  results: SearchQueryHit[];
  /** זמין מה-chunk הראשון; null רק אם המנוע טרם החזיר ספירה. */
  total: number | null;
  groupCount: number | null;
  /** `true` = שאילתה רחבה מדי; התוצאות והספירה חלקיות. */
  truncated: boolean;
  limit: number;
  offset: number;
  facets: string[];
  bookCounts?: Array<BookIdentity & { title: string; count: number }>;
}

export interface SearchOptionsCatalog {
  modes: SearchMode[];
  orders: SearchOrder[];
  proximityScopes: SearchProximityScope[];
  grouping: SearchGrouping[];
  wordMatchModes: SearchWordMatchMode[];
  wordOptions: { exact: string[]; advanced: string[]; vocalized: string[] };
  eras: string[];
  maxLimit: number;
  maxResultWindow: number;
  fuzzyMaxDistance: number;
  defaultLimit: number;
}

export interface NetworkFetchParams {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  /** ברירת מחדל 30,000; מקסימום 120,000 מילישניות. */
  timeoutMs?: number;
}

export type NetworkFetchStreamChunk =
  | {
      sequence: number;
      type: 'response';
      status: number;
      ok: boolean;
      /** שמות הכותרות מוחזרים באותיות קטנות. */
      headers: Record<string, string>;
    }
  | {
      sequence: number;
      type: 'data';
      /** מקטע UTF-8; גבול המקטע אינו בהכרח גבול שורה. */
      body: string;
    };

/**
 * הגדרות פתיחת טאב חיפוש (`reader.openSearchTab` → `settings`).
 * תת-קבוצה של פרמטרי `search.query`; הערכים החוקיים מ-`search.getOptions`.
 */
export interface OpenSearchTabSettings {
  /** ברירת מחדל 'advanced'. */
  mode?: SearchMode;
  /** מרווח מילים בין מילות החיפוש; במצב 'fuzzy' הטווח 0–2. */
  distance?: number;
  proximityScope?: SearchProximityScope;
  wordMatchMode?: SearchWordMatchMode;
  /** חוקי רק עם mode: 'advanced' ו-wordMatchMode: 'atLeast'. */
  wordMatchCount?: number;
  /** אפשרויות מילה שחלות על כל מילות השאילתה (למשל 'קידומות דקדוקיות'). */
  options?: Record<string, boolean>;
  /** אפשרויות פר-מילה במפתח `"{מילה}_{אינדקס}"`; גובר על `options`. */
  wordOptions?: Record<string, Record<string, boolean>>;
}

/** פרמטרי `reader.openSearchTab` — פתיחת כרטיסיית חיפוש מובנית. */
export interface OpenSearchTabArgs {
  query: string;
  /** ברירת מחדל true — הרצה אוטומטית; false פותח עם השאילתה בשדה בלי להריץ. */
  autoSearch?: boolean;
  /** שורות `searchDialogItems` של התוסף הקורא (עד 4 מזהים). */
  selectItems?: string[];
  /** הגדרות החיפוש איתן תיפתח הכרטיסייה. */
  settings?: OpenSearchTabSettings;
}

export interface TocEntry {
  text: string;
  index: number;
  level: number;
}

/**
 * מבנה תוכן-עניינים חלופי ("כותרות") של ספר, כפי שמוחזר מ-
 * `library.listBookAltStructures`. ה-`key` יציב בין גרסאות ספרייה ומשמש
 * כ-`structureKey` ב-`library.getBookAltToc`.
 */
export interface AltStructure {
  key: string;
  title: string | null;
  heTitle: string | null;
}

/**
 * מפרש של ספר כפי שמוחזר מ-`library.getCommentators`. `isRare` נכון רק
 * בקריאה ללא טווח שורות — הנדירות מוגדרת ביחס לספר כולו.
 */
export interface CommentatorInfo {
  title: string;
  author?: string;
  linkCount: number;
  isRare: boolean;
}

/** קבוצת מפרשים לפי דור, כפי שהממשק מציג אותה. */
export interface CommentatorGroup {
  title: string;
  commentators: string[];
}

export type GetCommentatorsResult =
  | { commentators: CommentatorInfo[] }
  | { groups: CommentatorGroup[] };

/** עוגן-מילה של קישור בשורת המקור (אופסטים בתווים גלויים). */
export interface LinkAnchor {
  start: number;
  end: number | null;
  label: string | null;
}

/** קישור יחיד כפי שמוחזר מ-`library.getLinks`. כל השורות 0-based. */
export interface BookLink {
  sourceLine: number;
  targetTitle: string;
  targetLine: number;
  /** סוף טווח בצד המקושר, או `null` לקישור לשורה בודדת. */
  targetLineEnd: number | null;
  targetHeRef: string;
  connectionType: string;
  /** `true` למפרש/תרגום/מדרש; `false` להפניה. */
  isCommentary: boolean;
  targetIsUserBook: boolean;
  targetCategoryId: number | null;
  /** מוחזר רק כאשר `includeAnchors: true` ולקישור יש עוגן. */
  anchor?: LinkAnchor;
}

export interface GetLinksResult {
  links: BookLink[];
  /** `true` כשהתשובה נחתכה בתקרת 2,000 הרשומות. */
  truncated: boolean;
}

/**
 * קישור יחיד בחמשת המפתחות של פורמט `links.json`, כפי שמוחזר מ-
 * `library.getRawLinks`.
 *
 * ⚠️ בניגוד לשאר ה-SDK, `line_index_1`/`line_index_2` הם **1-based** — זו
 * מוסכמת הפורמט. גם שגיאת הכתיב ב-`Conection Type` היא חלק ממנו.
 *
 * `start`/`end` מופיעים רק בספרים שהקישורים שלהם נקראים מקובץ ולא מהמסד.
 */
export interface RawBookLink {
  heRef_2: string;
  line_index_1: number;
  path_2: string;
  line_index_2: number;
  'Conection Type': string;
  start?: number;
  end?: number;
}

export interface GetRawLinksResult {
  links: RawBookLink[];
  /** `true` כשהתשובה נחתכה בתקרת 10,000 הרשומות. */
  truncated: boolean;
  /**
   * הטווח שנסרק בפועל (0-based, כולל). `endLine` הוא נקודת המשך תקפה רק
   * כש-`truncated` הוא `false`.
   */
  startLine: number;
  endLine: number;
}

export interface LinkTargetSummary {
  targetTitle: string;
  connectionType: string;
  linkCount: number;
}

export interface GetLinkTargetsSummaryResult {
  targets: LinkTargetSummary[];
  /** השורה הגבוהה ביותר שיש עליה קישור (0-based), או ‎-1‎ כשאין קישורים. */
  maxSourceLine: number;
}

export type LinkContentItem = { content: string } | { error: 'not_found' };

export interface GetLinkContentResult {
  /** באותו סדר של פריטי הקלט. */
  items: LinkContentItem[];
}

/** מצב המפרשים של טאב הקריאה (`reader.getActiveCommentators`). */
export interface ActiveCommentators {
  available: string[];
  active: string[];
  /** ריק בטאב PDF. */
  rare: string[];
  /** ריק בטאב PDF. */
  groups: CommentatorGroup[];
}

/** ארגומנטים ל-`reader.setActiveCommentators`. יש להעביר לפחות אחד. */
export interface SetActiveCommentatorsArgs {
  add?: string[];
  remove?: string[];
}

/** ארגומנטים ל-`reader.scrollToSection`. */
export interface ScrollToSectionArgs {
  /** בטקסט — אינדקס שורה (מבוסס-0); ב-PDF — מספר עמוד (מבוסס-1). */
  sectionIndex: number;
  /** ברירת מחדל false; false מנקה סימון קיים. */
  highlight?: boolean;
}

/** משטח הקריאה הנוכחי, כפי ש-`reader.getHighlightCapabilities` מדווח. */
export type ReaderSurface = 'combined' | 'pageShape' | 'pdf';

/** מה נתמך בפועל בהקשר הקריאה הנוכחי. */
export interface HighlightCapabilities {
  /** null כשאין חלונית קריאה פתוחה. */
  surface: ReaderSurface | null;
  /** הדגשות מצוירות רק בטור הטקסט הראשי, ולא ב-PDF. */
  highlights: boolean;
  /** בחירת טקסט אינה נתמכת ב-PDF. */
  selection: boolean;
  /** האזורים שבהם פריטי תפריט הקשר של תוספים מוצגים. */
  contextMenu: string[];
}

/**
 * שולחן עבודה — אוסף הכרטיסיות הפתוחות (`workspace.list`).
 */
export interface WorkspaceListEntry {
  id: string;
  name: string;
  isActive: boolean;
  /**
   * מספר הכרטיסיות שה-API חושף — אותן כרטיסיות שב-`ReaderState.openTabs`.
   * כרטיסיות של כלים ותוספים אינן נמנות. בשולחן הפעיל זו הספירה החיה.
   */
  tabCount: number;
}

/** השולחן הפעיל (`workspace.getActive`). `null` כשעדיין לא נטען שולחן. */
export interface ActiveWorkspace {
  id: string | null;
  name: string | null;
}

/** ארגומנטים ל-`workspace.create`. */
export interface WorkspaceCreateArgs {
  /** עד 100 תווים; שם ריק נדחה ב-`error.invalid_params`. */
  name: string;
  /** מעבר לשולחן מיד לאחר היצירה. ברירת מחדל `false`. */
  switchTo?: boolean;
  /** החזרת שולחן קיים באותו שם במקום יצירת כפילות. ברירת מחדל `false`. */
  reuseExisting?: boolean;
}

/** תוצאת `workspace.create`. `created: false` = הוחזר שולחן קיים. */
export interface WorkspaceCreateResult {
  id: string;
  created: boolean;
}

/** סימנייה (`bookmarks.list`). */
export interface BookmarkEntry extends BookIdentity {
  title: string;
  ref: string;
  /** בטקסט — אינדקס שורה; ב-PDF — מספר עמוד. */
  index: number;
  label: string | null;
  targetKind: 'book' | 'commentators';
  /** ISO 8601; null בסימניות מגרסאות קודמות. */
  createdAt: string | null;
}

/**
 * ארגומנטים ל-`reader.closeTab` ול-`reader.activateTab`.
 *
 * ה-index הוא המקום ב-`ReaderState.openTabs` — לא מקומה של הכרטיסייה בשורת
 * הכרטיסיות. אינדקס מחוץ לתחום מוחזר כ-`error.invalid_params`.
 */
export interface ReaderTabIndexArgs {
  index: number;
}

/** ארגומנטים ל-`bookmarks.add`. הספר מזוהה ב-`id` או ב-`bookId`. */
export interface BookmarkAddArgs extends BookIdentity {
  index?: number;
  /** כשאינו נמסר — מחושב מתוכן העניינים של הספר. */
  ref?: string;
  label?: string;
}

/** ארגומנטים ל-`bookmarks.remove`. */
export interface BookmarkRemoveArgs extends BookIdentity {
  /** ללא index — הסימנייה הראשונה של הספר. */
  index?: number;
}

export type GematriaMethod = 'regular' | 'small' | 'finalLetters';

/** ארגומנטים ל-`tools.gematria`. עד 2000 תווים. */
export interface GematriaArgs {
  text: string;
  /** ברירת מחדל 'regular'. */
  method?: GematriaMethod;
  /** "עם הכולל" — מוסיף את מספר המילים לערך. */
  withKolel?: boolean;
}

/** תוצאת `tools.gematria`. */
export interface GematriaResult {
  value: number;
  method: GematriaMethod;
  /** מספר המילים בקלט — הבסיס ל-withKolel. */
  words: number;
}

/** תוצאת `tools.dictionary`. */
export interface DictionaryLookupResult {
  term: string;
  acronyms: Array<{ acronym: string; meanings: string[] }>;
  /** `hebrew` הוא טקסט עם סימון מקורי. */
  aramaic: Array<{ aramaic: string; hebrew: string }>;
}

export type JewishHolidayKind =
  | 'yomTov'
  | 'roshChodesh'
  | 'taanit'
  | 'special';

export interface JewishHoliday {
  text: string;
  kind: JewishHolidayKind;
}

export interface JewishDate {
  year: number;
  month: number;
  day: number;
  /** ISO 8601 Gregorian equivalent */
  gregorian: string;
  monthName: string;
  isLeapYear: boolean;
  isShabbat: boolean;
  holidays: JewishHoliday[];
}

export interface CalendarEvent {
  id: string;
  title: string;
  /** ISO 8601 */
  date: string;
  description: string;
}

/** Arguments for `calendar.getDailyTimes` and `calendar.getHalachicTimes`. */
export interface CalendarTimesArgs {
  /** ISO 8601 date. Defaults to the calendar's selected date. */
  date?: string;
  /** A city returned by `calendar.getCities`. Mutually exclusive with coordinates. */
  city?: string;
  /** Latitude. Must be supplied together with `lng`. */
  lat?: number;
  /** Longitude. Must be supplied together with `lat`. */
  lng?: number;
  /** Elevation in metres. Defaults to 0. */
  elevation?: number;
  /** IANA time-zone identifier. */
  timezone?: string;
  /** Whether to use the Israel holiday calendar. */
  inIsrael?: boolean;
}

/** A city supported by the built-in calendar. */
export interface CityInfo {
  name: string;
  country: string;
  lat: number;
  lng: number;
  elevation: number;
  timezone: string;
  inIsrael: boolean;
}

export interface ReaderState {
  currentBook: string | null;
  currentBookId: string | null;
  /** מזהה ספר יציב של הטאב הפעיל (`null` לטאב שאינו ספר / אין טאב). ראה `BookMeta.bookUid`. */
  bookUid: string | null;
  /** Canonical book id of the active tab (`null` for a non-book tab / no tab). */
  currentId: number | null;
  currentType: BookType | null;
  currentSource: 'library' | 'user' | 'external' | null;
  currentIndex: number;
  currentRef: string | null;
  openTabs: Array<{
    /** Canonical book id (`null` for a non-book tab such as search). */
    id: number | null;
    type: BookType | null;
    source: 'library' | 'user' | 'external' | null;
    bookId: string;
    /** מזהה ספר יציב (`null` לטאב שאינו ספר). ראה `BookMeta.bookUid`. */
    bookUid: string | null;
    book: string;
    index: number;
    currentRef: string | null;
  }>;
}

export interface ReaderRefState {
  currentBook: string | null;
  currentBookId: string | null;
  /** מזהה ספר יציב (`null` כשאין טאב ספר פעיל). ראה `BookMeta.bookUid`. */
  bookUid: string | null;
  /** Canonical book id of the active tab (`null` when no book tab is active). */
  currentId: number | null;
  currentType: BookType | null;
  currentSource: 'library' | 'user' | 'external' | null;
  currentIndex: number;
  currentRef: string | null;
}

export interface ReaderSelection {
  /** Legacy fields, retained for backward compatibility. */
  text: string;
  start: number | null;
  end: number | null;
  currentRef: string | null;
  currentBook: string;
  currentBookId: string;
  /** מזהה ספר יציב של הספר שממנו נבחר הטקסט. ראה `BookMeta.bookUid`. */
  bookUid?: string;
  currentIndex: number;
  /** Present when the Host can verify the selected range against the section. */
  schemaVersion?: 1;
  selectionId?: string;
  bookId?: string;
  bookTitle?: string;
  tabId?: string;
  sectionIndex?: number;
  sectionId?: string;
  renderedSelectedText?: string;
  sourceSelectedText?: string;
  normalizedSelectedText?: string;
  sourceRange?: TextRangeAnchor;
  renderedRange?: TextRangeAnchor;
  direction?: 'rtl' | 'ltr' | 'mixed';
  /** ISO 8601 */
  createdAt?: string;
  /** Multi-paragraph selection: one fully-anchored entry per section, in
   * reading order. The top-level fields then carry no sourceRange. From 0.9.97. */
  sections?: ReaderSelectionSection[];
  /** `reader-highlight` context only: the plugin highlights found under the
   * click position. Act only on your own ids. From 0.9.97. */
  clickedHighlights?: ClickedHighlightRef[];
}

/** One section of a multi-paragraph selection (same shape as a verified
 * single-section selection, scoped to that section). */
export interface ReaderSelectionSection {
  schemaVersion: 1;
  selectionId: string;
  bookId: string;
  bookTitle?: string;
  sectionIndex: number;
  /** Mirrors `sectionIndex` for legacy consumers. */
  currentIndex: number;
  currentRef: string | null;
  renderedSelectedText: string;
  sourceSelectedText: string;
  normalizedSelectedText: string;
  sourceRange: TextRangeAnchor;
  renderedRange: TextRangeAnchor;
  direction: 'rtl' | 'ltr' | 'mixed';
  /** ISO 8601 */
  createdAt: string;
}

export interface ClickedHighlightRef {
  highlightId: string;
  /** Owner plugin id — skip entries that are not yours. */
  pluginId: string;
}

export interface TextOffset {
  grapheme: number;
  codePoint?: number;
  utf16?: number;
}

export interface AnchorContext {
  raw: string;
  normalized?: string;
  maxGraphemes: number;
  actualGraphemes: number;
  truncatedAtBoundary: boolean;
}

export interface TextRangeAnchor {
  type: 'text-range-v1';
  schemaVersion: 1;
  layer: 'source' | 'rendered';
  sourceTextHash?: string;
  renderedTextHash?: string;
  start: TextOffset;
  end: TextOffset;
  exactText: string;
  beforeText: AnchorContext;
  afterText: AnchorContext;
  occurrenceIndexInSection: number;
  occurrenceCountInSection: number;
  startWordIndex?: number;
  endWordIndex?: number;
  normalizationProfile?: 'strict' | 'display' | 'search' | 'lenient';
}

export type NormalizationProfileName =
  | 'strict'
  | 'display'
  | 'search'
  | 'lenient';

export interface NormalizeOptions {
  profile: NormalizationProfileName;
  overrides?: {
    ignoreNikud?: boolean;
    ignoreTeamim?: boolean;
    ignorePunctuation?: boolean;
    normalizeWhitespace?: boolean;
    normalizeFinalLetters?: boolean;
  };
}

export interface FindTextOccurrencesArgs {
  bookId: string;
  sectionIndex: number;
  query: string;
  layer?: 'source' | 'rendered';
  normalize?: NormalizeOptions;
  /** 1-200; defaults to 50. */
  limit?: number;
  cursor?: string;
}

export interface TextOccurrence {
  occurrenceId: string;
  bookId: string;
  sectionIndex: number;
  currentRef: string | null;
  layer: 'source' | 'rendered';
  text: string;
  normalizedText: string;
  range: TextRangeAnchor;
}

export interface FindTextOccurrencesResult {
  schemaVersion: 1;
  results: TextOccurrence[];
  hasMore: boolean;
  nextCursor?: string;
  totalCount: number;
}

export interface TextSourceMapSegment {
  sourceStart: TextOffset;
  sourceEnd: TextOffset;
  renderedStart: TextOffset;
  renderedEnd: TextOffset;
  kind:
    | 'identity'
    | 'substitution'
    | 'hidden'
    | 'inserted';
  description?: string;
}

export interface TextSourceMap {
  schemaVersion: 1;
  bookId: string;
  sectionIndex: number;
  sourceTextHash: string;
  renderedTextHash: string;
  mappings: TextSourceMapSegment[];
}

export interface GetSectionTextMapArgs {
  bookId: string;
  sectionIndex: number;
  layer?: 'source' | 'rendered' | 'both';
  includeWords?: boolean;
  includeChars?: boolean;
  includeSourceMap?: boolean;
  normalize?: NormalizeOptions;
  /** 1-2000; defaults to 500. */
  limit?: number;
  cursor?: string;
}

export interface WordToken {
  wordIndex: number;
  layer: 'source' | 'rendered';
  text: string;
  normalizedText: string;
  start: TextOffset;
  end: TextOffset;
  sourceRange?: TextRangeAnchor;
  renderedRange?: TextRangeAnchor;
}

export interface CharToken {
  /** Grapheme-cluster index, not a UTF-16 code-unit index. */
  charIndex: number;
  layer: 'source' | 'rendered';
  text: string;
  normalizedText: string;
  start: TextOffset;
  end: TextOffset;
}

export interface SectionTextMapResult {
  schemaVersion: 1;
  bookId: string;
  sectionIndex: number;
  currentRef: string | null;
  sourceText?: string;
  renderedText?: string;
  sourceTextHash?: string;
  renderedTextHash?: string;
  sourceMap?: TextSourceMap;
  words?: WordToken[];
  chars?: CharToken[];
  hasMore: boolean;
  nextCursor?: string;
}

export interface HighlightStyle {
  /** Safe CSS color: #RRGGBB or #RRGGBBAA. */
  backgroundColor: string;
  foregroundColor?: string;
  opacity?: number;
  underline?: boolean;
  underlineColor?: string;
  borderRadius?: number;
  markerMode?: 'text-background' | 'line-marker' | 'box' | 'underline';
  priority?: number;
}

export interface HighlightMetadataInput {
  note?: string;
  tags?: string[];
  source?: 'manual' | 'ai' | 'import' | 'sync';
}

export interface SetHighlightArgs {
  highlightId?: string;
  bookId: string;
  /**
   * מזהה ספר יציב (ראה `BookMeta.bookUid`). מומלץ מאוד לשלוח אותו: הדגשה
   * שנשמרה עם `bookUid` שורדת שינוי כותרת ואינה מתנגשת עם ספר אחר בעל אותו
   * שם. הדגשה ישנה שנשמרה עם `bookId` (כותרת) בלבד ממשיכה להימצא כמקודם.
   */
  bookUid?: string;
  sectionIndex: number;
  range: TextRangeAnchor;
  style: HighlightStyle;
  metadata?: HighlightMetadataInput;
}

export interface UpdateHighlightArgs {
  highlightId: string;
  /** Reject the update with error.conflict if the current version differs. */
  expectedVersion?: number;
  expectedEtag?: string;
  style?: Partial<HighlightStyle>;
  metadata?: Partial<HighlightMetadataInput>;
}

export interface HighlightRecord {
  schemaVersion: 1;
  highlightId: string;
  ownerPluginId: string;
  bookId: string;
  /** מזהה ספר יציב, כשההדגשה נשמרה איתו. ראה `BookMeta.bookUid`. */
  bookUid?: string;
  sectionIndex: number;
  currentRef: string | null;
  range: TextRangeAnchor;
  style: HighlightStyle;
  metadata: HighlightMetadataInput;
  status: 'active' | 'stale' | 'failed_to_anchor';
  version: number;
  etag: string;
  createdAt: string;
  updatedAt: string;
}

export interface ClearHighlightArgs {
  highlightId: string;
  expectedVersion?: number;
  expectedEtag?: string;
}

export interface ReaderSectionContentChangedEvent {
  schemaVersion: 1;
  bookId: string;
  sectionIndex: number;
  oldSourceTextHash?: string;
  newSourceTextHash: string;
  oldRenderedTextHash?: string;
  newRenderedTextHash?: string;
  changeType: 'source-content' | 'rendering-only';
  reason?:
    | 'book-updated'
    | 'settings-changed'
    | 'nikud-toggle'
    | 'teamim-toggle'
    | 'font-render-change'
    | 'name-substitution'
    | 'layout-change';
}

export type ContextMenuContext =
  | 'reader-selection'
  | 'reader-page-shape-selection'
  /** Right-click on a plugin highlight, with or without an active selection.
   * The click payload carries `selection.clickedHighlights`. From 0.9.97. */
  | 'reader-highlight';

export interface ContextMenuColor {
  id: string;
  /** Safe CSS color: #RRGGBB or #RRGGBBAA. */
  color: string;
  label: string;
  /** Optional icon rendered instead of the color swatch. See ICONS.md. */
  icon?: string;
  selected?: boolean;
}

/**
 * A top-level reader context-menu registration or a nested child item.
 * A plugin may register at most two top-level items; replacing the same `id`
 * does not consume another slot.
 */
export interface ContextMenuItem {
  id: string;
  type?: 'item' | 'submenu' | 'color-row' | 'separator';
  /** `label` is accepted as a legacy alias. */
  title?: string;
  label?: string;
  /** Icon name (see ICONS.md). */
  icon?: string;
  /** One or more reader contexts. Children inherit this when omitted; an
   * explicit child value must be a subset of its parent's contexts. */
  contexts?: ContextMenuContext[];
  /** Custom event dispatched only to the owning plugin. */
  onClickEvent?: string;
  /** Custom color event dispatched only to the owning plugin. */
  onColorClickEvent?: string;
  children?: ContextMenuItem[];
  colors?: ContextMenuColor[];
  /** When true, clicking opens the plugin page and the click event is
   * delivered to it after boot. Available from 0.9.96. */
  openPlugin?: boolean;
  /** Free-form value echoed back as `param` in the click event payload. */
  param?: unknown;
  /** Show the item only when the selected text matches. Available from 0.9.97. */
  showWhen?: ContextMenuShowWhen;
}

/**
 * Content-dependent visibility for a context-menu item. Word list only —
 * regex is intentionally unsupported.
 */
export interface ContextMenuShowWhen {
  /** Show only when the selection contains at least one of these strings
   * (1-50 strings, each up to 100 characters). */
  selectionContainsAny: string[];
}

export interface UpdateContextMenuItemArgs {
  id: string;
  patch: Partial<Omit<ContextMenuItem, 'id'>>;
}

export interface ContextMenuItemClickedEvent {
  itemId: string;
  selection: ReaderSelection;
  /** Legacy fields retained for existing plugins. */
  selectedText: string;
  currentRef: string | null;
  currentBook: string;
  currentBookId: string;
  currentIndex: number;
  /** The `param` value passed to `reader.addContextMenuItem`, or null. */
  param: unknown;
}

export interface ContextMenuColorClickedEvent {
  itemId: string;
  colorId: string;
  color: string;
  selection: ReaderSelection;
}

export type ToolbarContext = 'reader-text' | 'reader-pdf';

/**
 * A reader-toolbar registration: a single button, a dropdown menu whose
 * children are buttons, or a split button (a main action plus an arrow that
 * opens the children). A plugin may register at most two top-level items;
 * replacing the same `id` does not consume another slot. Available from 0.9.97.
 */
export interface ToolbarItem {
  id: string;
  type?: 'button' | 'menu' | 'split';
  /** Tooltip on the visible button and label in the overflow menu. */
  title: string;
  /** Icon name (see ICONS.md). Required on top-level items, optional on children. */
  icon?: string;
  /** One or more reader contexts. Children inherit this when omitted; an
   * explicit child value must be a subset of its parent's contexts. */
  contexts?: ToolbarContext[];
  /** Custom event dispatched only to the owning plugin. */
  onClickEvent?: string;
  /** Children (`type: 'menu'` or `'split'`, up to 20 buttons, no nesting). */
  children?: ToolbarItem[];
  /** When true, clicking opens the plugin page and the click event is
   * delivered to it after boot. */
  openPlugin?: boolean;
  /** Free-form value echoed back as `param` in the click event payload. */
  param?: unknown;
}

export interface UpdateToolbarItemArgs {
  id: string;
  patch: Partial<Omit<ToolbarItem, 'id'>>;
}

export interface ToolbarItemClickedEvent {
  /** For a menu click this is the id of the selected child. */
  itemId: string;
  context: ToolbarContext;
  currentBook: string | null;
  currentBookId: string | null;
  currentId: number | null;
  currentType: string | null;
  currentSource: string | null;
  currentIndex: number;
  currentRef: string | null;
  /** The `param` value passed to `reader.addToolbarItem`, or null. */
  param: unknown;
}

export type ApiErrorCategory =
  | 'permission'
  | 'validation'
  | 'not_found'
  | 'conflict'
  | 'timeout'
  | 'too_large'
  | 'internal'
  | 'unsupported';

export interface ApiError {
  schemaVersion: 1;
  code: string;
  message: string;
  details?: unknown;
  retryable: boolean;
  category: ApiErrorCategory;
}

export type PublishedDataType =
  | 'calendar.event'
  | 'saved.query'
  | 'note.draft'
  | 'reference.link'
  | 'tool.badge';

export interface PublishedRecord<TPayload = unknown> {
  type: PublishedDataType;
  /** 'global' | 'workspace:<id>' | 'book:<bookUid>' (מזוהה גם 'book:<כותרת>' לתאימות) */
  scope: string;
  key: string;
  payload: TPayload;
}

/** Payload shape for a `calendar.event` published record */
export interface CalendarEventPayload {
  title: string;
  /** ISO 8601 */
  startsAt: string;
  /** ISO 8601 (optional) */
  endsAt?: string;
  source: string;
  importance?: 'high' | 'medium' | 'low';
  description?: string;
}

// ---------------------------------------------------------------------------
// Event map
// ---------------------------------------------------------------------------

export interface OtzariaEventMap {
  /** Fired once after the SDK is ready, carries full boot context. */
  'plugin.boot': BootPayload;
  /** Fired once after boot. Payload is null. */
  'plugin.ready': null;
  /** The plugin's foreground WebView is about to be paused (user navigated away). Payload is null. */
  'plugin.suspended': null;
  /** The plugin's foreground WebView was resumed (user navigated back). Payload is null. */
  'plugin.resumed': null;
  /** Theme / dark-mode changed. */
  'theme.changed': ThemePayload;
  /** Top-level screen navigation changed. */
  /**
   * שים לב: 'more' אינו משודר יותר — כלים ותוספים חיים ככרטיסיות בתוך
   * 'reading'. כדי לדעת אם התוסף מוצג כעת השתמש ב-plugin.suspended /
   * plugin.resumed. הערך נשמר בטיפוס לתאימות אחורה.
   */
  'navigation.changed': { screen: 'library' | 'reading' | 'more' | 'settings' };
  /** Active book in the reader changed. */
  'reader.current_book_changed': { book: string; index: number };
  /** Current reading location changed (page, chapter, section). */
  'reader.current_ref_changed': {
    currentBook: string | null;
    currentBookId: string | null;
    currentIndex: number;
    currentRef: string | null;
  };
  /** Selected calendar date changed. */
  'calendar.date_changed': { date: string };
  /** Selected calendar city changed. */
  'calendar.city_changed': { city: string };
  /** Active workspace changed. */
  'workspace.changed': { workspaceId: string };
  /** A whitelisted app setting changed. */
  'settings.changed': { key: string; newValue: unknown };
  /** Permissions snapshot changed (list of all currently granted permissions). */
  'plugin.permissions_changed': { permissions: string[] };
  /** User selected text in the reader. Requires permission: events.subscribe:reader.selection_changed */
  'reader.selection_changed': {
    text: string;
    currentRef: string;
    currentBook: string;
    currentBookId: string;
    currentIndex: number;
  };
  /**
   * A keyboard shortcut bound to a free-form command was pressed in the reading
   * screen. Sent only to the registering plugin.
   */
  'app.command': PluginCommandPayload;
  /** User clicked a plugin-registered context menu item. Sent only to the registering plugin. */
  'reader.context_menu_item_clicked': {
    itemId: string;
    selectedText: string;
    currentRef: string;
    currentBook: string;
    currentBookId: string;
    currentIndex: number;
    /** The `param` value passed to `reader.addContextMenuItem`, or null. */
    param: unknown;
  };
  /**
   * The plugin page was opened via `plugin.openSelf`, or by another plugin via
   * `plugin.openOther` — in which case `openedBy` holds that plugin's id.
   */
  'plugin.page_opened': { param: unknown; openedBy?: string };
  /** A checked static search row routed submission to its owning plugin. */
  'search.requested': { itemId: string; request: SearchQueryParams };
  /** External-search page request sent only to the plugin owning `provider`. */
  'search.external.requested': {
    requestId: string;
    provider: string;
    query: string;
    mode: 'exact' | 'advanced' | 'fuzzy';
    distance: number;
    offset: number;
    limit: number;
    ids?: number[];
    /** The host consumes `[id, hits, categoryPath, title]` index entries. */
    indexTitles?: boolean;
  };
  /** In-book search request sent only to the plugin owning `provider`. */
  'reader.inBookSearch.requested': {
    requestId: string;
    provider: string;
    externalId: number | string;
    query: string;
  };
  /** Standard context-menu click event. Sent only to the owning plugin. */
  'contextMenu.itemClicked': ContextMenuItemClickedEvent;
  /** Standard color-row click event. Sent only to the owning plugin. */
  'contextMenu.colorClicked': ContextMenuColorClickedEvent;
  /** User clicked a plugin-registered toolbar item. Sent only to the registering plugin. */
  'reader.toolbar_item_clicked': ToolbarItemClickedEvent;
  'reader.sectionContentChanged': ReaderSectionContentChangedEvent;
  /**
   * The user tapped a clickable message shown via `ui.show*` /
   * `notifications.showInApp`. Sent only to the plugin that raised the message,
   * and only when it was raised with a `tapPayload` (and no explicit `tapEvent`
   * overriding the topic). `payload` echoes back that `tapPayload`.
   */
  'ui.messageClicked': { payload: unknown };
}

/** 'more' נשמר לתאימות אחורה — פותח את פאנל הכלים. */
export type NavigationTarget = 'library' | 'reading' | 'more' | 'settings';

// ---------------------------------------------------------------------------
// All valid method strings
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Database types
// ---------------------------------------------------------------------------

export interface DatabaseSourceSummary {
  id: string;
  label: string;
  available: boolean;
}

export interface DatabaseTableSchema {
  name: string;
  columns: string[];
}

export interface DatabaseSourceDescription {
  source: { id: string; label: string };
  schema: { tables: DatabaseTableSchema[] };
  limits: {
    maxLimit: number;
    maxBatchQueries: number;
    maxQueryDurationMs: number;
  };
}

export interface DatabaseSelectItem {
  expr: string;
  as?: string;
}

export interface DatabaseJoinCondition {
  left: string;
  op: '=';
  right: string;
}

export interface DatabaseJoin {
  type: 'inner' | 'left';
  table: string;
  alias?: string;
  on: DatabaseJoinCondition[];
}

export type DatabaseWhereOp =
  | '=' | '!=' | '>' | '>=' | '<' | '<='
  | 'in' | 'between' | 'like'
  | 'isNull' | 'isNotNull';

export interface DatabaseWhereLeaf {
  op: DatabaseWhereOp;
  left: string;
  value?: unknown;
}

export interface DatabaseWhereNode {
  op: 'and' | 'or';
  conditions: DatabaseWhereCondition[];
}

export type DatabaseWhereCondition = DatabaseWhereLeaf | DatabaseWhereNode;

export interface DatabaseOrderBy {
  expr: string;
  direction?: 'asc' | 'desc';
}

export interface DatabaseQuerySpec {
  sourceId: string;
  from: { table: string; alias?: string };
  select: DatabaseSelectItem[];
  joins?: DatabaseJoin[];
  where?: DatabaseWhereCondition;
  orderBy?: DatabaseOrderBy[];
  limit?: number;
  offset?: number;
  rowFormat?: 'array' | 'object';
}

export interface DatabaseQueryMeta {
  sourceId: string;
  rowCount: number;
  limit: number;
  offset: number;
  hasMore: boolean;
  elapsedMs: number;
}

export interface DatabaseColumnMeta {
  name: string;
}

export interface DatabaseQueryResult {
  meta: DatabaseQueryMeta;
  columns: DatabaseColumnMeta[];
  /** array format: each row is an array of values in columns order */
  rows: unknown[][] | Record<string, unknown>[];
}

export interface DatabaseBatchQuerySpec {
  queries: DatabaseQuerySpec[];
}

export interface DatabaseBatchQueryResult {
  results: DatabaseQueryResult[];
}

export interface InstalledPlugin {
  pluginId: string;
  name: string;
  version: string;
  enabled: boolean;
  showInTools: boolean;
  toolTabIconName: string;
}

/** Where a `shortcut.create` deep-link shortcut is placed. `startMenu` is Windows-only. */
export type ShortcutLocation = 'desktop' | 'startMenu';

/**
 * Arguments for `shortcut.create`. The shortcut always opens the calling plugin
 * (`otzaria://open/plugin/<id>`); the host builds the deep-link itself, so the
 * plugin only supplies a display name and an optional location.
 */
export interface ShortcutCreateArgs {
  /** Display name and file name of the shortcut. */
  label: string;
  /** Target location. Defaults to `'desktop'`. */
  location?: ShortcutLocation;
}

/** Result of `shortcut.create`. */
export interface ShortcutCreateResult {
  /** `false` when the user declined the confirmation dialog. */
  created: boolean;
  /** Absolute path of the created shortcut file (present only when `created` is `true`). */
  path?: string;
}

/** קובץ אישי מאושר — התוצאה של `fs.resolveFileUrl`. */
export interface UserFileHandle {
  /** מזהה אטום ששורד טעינה מחדש. יש לשמור אותו, לא את ה-URL. */
  token: string;
  /** URL מ-loopback, תקף לריצה הנוכחית בלבד (הפורט מתחלף). */
  url: string;
  name: string;
  size: number;
}

/**
 * תוצאת `fs.pickUserFile`. בביטול חוזר `{ cancelled: true }` בלבד, ולכן זהו
 * union ולא אובייקט עם שדות אופציונליים.
 */
export type PickUserFileResult =
  | { cancelled: true }
  | ({
      cancelled: false;
      /** קיים מ-0.9.97. `readwrite` = ניתן לשמש כ-`targetToken` בכתיבה. */
      access?: 'read' | 'readwrite';
    } & UserFileHandle);

/** תוצאת `fs.beginBinaryWrite` — לאן לשלוח את הבייטים ועד מתי. */
export interface BinaryWriteTicket {
  /** חד-פעמי, פג תוך שתי דקות. */
  writeToken: string;
  /** יעד ל-PUT יחיד עם `Content-Length`. */
  uploadUrl: string;
  /** ISO-8601. */
  expiresAt: string;
  maxBytes: number;
}

/** תוצאת `fs.commitUserFileWrite`. */
export interface UserFileWriteResult {
  /** `true` כשהמשתמש ביטל את „שמור בשם”. אין שינוי בקובץ ובהרשאות. */
  cancelled: boolean;
  /** token לכתיבה — אפשר להעביר אותו כ-`targetToken` בשמירה הבאה. */
  token?: string;
  name?: string;
  size?: number;
}

/**
 * The plugin's private file workspace (`fs.*`, since 0.9.97). No permission is
 * required: every path is relative to the plugin's own root and cannot leave it
 * (`..`, absolute paths, UNC and out-of-root symlinks are rejected with
 * `error.forbidden`). Quota: 100MB per plugin; 10MB per single read/write.
 */
export type WorkspaceEncoding = 'utf8' | 'base64';

export interface WorkspaceEntry {
  /** Path relative to the workspace root, '/'-separated. */
  path: string;
  name: string;
  type: 'file' | 'dir';
  /** Always 0 for directories. */
  size: number;
  /** ISO-8601 UTC, or null when unavailable. */
  modified: string | null;
}

export interface WorkspaceWriteArgs {
  path: string;
  content: string;
  /** Defaults to `'utf8'`. */
  encoding?: WorkspaceEncoding;
  /** Append to an existing file instead of replacing it. */
  append?: boolean;
}

export interface WorkspaceWriteResult {
  path: string;
  size: number;
  usedBytes: number;
  quotaBytes: number;
}

export interface WorkspaceReadResult {
  path: string;
  encoding: WorkspaceEncoding;
  size: number;
  content: string;
}

export interface WorkspaceListResult {
  path: string;
  entries: WorkspaceEntry[];
  usedBytes: number;
  quotaBytes: number;
}

/** Result of `fs.stat`: `WorkspaceEntry` fields are present only when it exists. */
export type WorkspaceStatResult =
  | ({ exists: true } & WorkspaceEntry)
  | { exists: false };

/**
 * A keyboard shortcut the plugin declares (manifest `contributes.startup.shortcuts`
 * or runtime `app.registerShortcut`). Pressing it in the reading screen either
 * sends an `app.command` event to the plugin (`command`) or triggers a
 * right-click menu action exactly like a right-click on it (`contextMenuItemId`).
 */
export interface PluginShortcutArgs {
  /** Unique id within the plugin. */
  id: string;
  /** Display label shown in the keyboard-shortcut settings screen. */
  label: string;
  /** Default key in canonical form (`ctrl+alt+x`); empty = user assigns one. */
  key?: string;
  /** Free-form command name, delivered to the plugin via the `app.command` event. */
  command?: string;
  /** Id of a context-menu item (`reader.addContextMenuItem`) this shortcut triggers. */
  contextMenuItemId?: string;
}

/** Arguments for `app.updateShortcut`. Only `key` is currently supported. */
export interface PluginShortcutUpdateArgs {
  id: string;
  patch: { key?: string };
}

/** Payload of the `app.command` event delivered when a command shortcut is pressed. */
export interface PluginCommandPayload {
  /** The `command` value passed to `app.registerShortcut` / manifest. */
  command: string;
  /** The shortcut id that triggered the command. */
  shortcutId: string;
}
/**
 * One entry of `fonts.resolveFamilies`: a family the document asks for, and the
 * fonts that may stand in for it, best first.
 */
export interface FontFamilyRequest {
  /** The family name as the document writes it. The returned face carries it. */
  name: string;
  /** Stand-ins to try in order; the first one the host can supply wins. */
  substitutes: string[];
}

/**
 * Result of `fonts.resolveFamilies`: ready-to-inject `@font-face` rules whose
 * bytes come from Otzaria's bundled or system fonts, each declared under the
 * requested `name`.
 *
 * Needed because `src: local()` inside a plugin WebView resolves only fonts
 * installed on the machine — never the faces Otzaria injects itself. A plugin
 * that renders a document asking for a font nobody installed cannot reach the
 * bundled fonts without the bytes.
 */
export interface ResolveFontFamiliesResult {
  /** The `@font-face` rules, newline-separated. Empty when nothing matched. */
  css: string;
  /** The requested names that got a face. */
  resolved: string[];
}

/**
 * One installed font family, from `fonts.listInstalled`.
 */
export interface InstalledFontFamily {
  /**
   * Exactly what CSS `font-family` accepts — not a file name, not "David Bold".
   *
   * On Windows GDI truncates a family name at 31 characters, so
   * `Bahnschrift SemiBold SemiCondensed` arrives as
   * `Bahnschrift SemiBold SemiConden`.
   */
  name: string;
  /** Which writing systems the family covers. */
  scripts: Array<
    'latin' | 'hebrew' | 'arabic' | 'cyrillic' | 'greek' | 'cjk' | 'thai' | 'symbol'
  >;
  /** `true` for a fixed-pitch family such as Consolas. */
  monospace: boolean;
}

/**
 * Result of `fonts.listInstalled`: the font families present on this machine.
 *
 * Lets a plugin see what actually exists before it picks a substitute, instead
 * of guessing or probing `fonts.resolveFamilies` family by family. A platform
 * with no implementation returns an empty `families` — that is not an error.
 *
 * Legacy Windows raster fonts (`.fon`) are excluded: a WebView cannot render
 * them, so their names would not be usable in CSS.
 */
export interface ListInstalledFontsResult {
  /** The installed families, sorted by name, each name appearing once. */
  families: InstalledFontFamily[];
  /** The host platform, e.g. `'windows'`. */
  platform: string;
}

export type OtzariaMethod =
  | 'app.getInfo'
  | 'app.getTheme'
  | 'app.getLocale'
  | 'app.getUserEmail'
  | 'app.getGrantedPermissions'
  | 'app.getConnectivity'
  | 'app.openUrl'
  | 'fonts.resolveFamilies'
  | 'fonts.listInstalled'
  | 'app.registerShortcut'
  | 'app.unregisterShortcut'
  | 'app.updateShortcut'
  | 'library.findBooks'
  | 'library.getBookMetadata'
  | 'library.resolveBooks'
  | 'library.resolveCategoryPaths'
  | 'library.getTree'
  | 'library.listRecentBooks'
  | 'library.getBookContent'
  | 'library.getBookToc'
  | 'library.listBookAltStructures'
  | 'library.getBookAltToc'
  | 'library.getCommentators'
  | 'library.getLinks'
  | 'library.getRawLinks'
  | 'library.getLinkTargetsSummary'
  | 'library.getLinkContent'
  | 'library.refreshUserBooks'
  | 'library.getTree'
  | 'library.resolveCategoryPaths'
  | 'search.fullText'
  | 'search.query'
  | 'search.getOptions'
  | 'reader.openBook'
  | 'reader.openBookAtRef'
  | 'reader.registerInBookSearchProvider'
  | 'reader.respondInBookSearch'
  | 'reader.openSearchTab'
  | 'reader.registerExternalSearchProvider'
  | 'reader.respondExternalSearch'
  | 'reader.getCurrentState'
  | 'reader.getCurrentRef'
  | 'reader.closeTab'
  | 'reader.activateTab'
  | 'reader.getSelection'
  | 'reader.getActiveCommentators'
  | 'reader.setActiveCommentators'
  | 'reader.scrollToSection'
  | 'reader.getHighlightCapabilities'
  | 'reader.findTextOccurrences'
  | 'reader.getSectionTextMap'
  | 'workspace.list'
  | 'workspace.getActive'
  | 'workspace.create'
  | 'workspace.switch'
  | 'navigation.goTo'
  | 'notes.list'
  | 'notes.getBookNotesSummary'
  | 'notes.add'
  | 'notes.update'
  | 'notes.delete'
  | 'ui.showMessage'
  | 'ui.showSuccess'
  | 'ui.showError'
  | 'ui.showConfirm'
  | 'ui.showWarning'
  | 'ui.pickFolder'
  | 'ui.print'
  | 'ui.exportPdf'
  | 'fs.extractZip'
  | 'fs.deleteFile'
  | 'fs.pickUserFile'
  | 'fs.resolveFileUrl'
  | 'fs.readTextFile'
  | 'fs.revokeFile'
  | 'fs.writeFile'
  | 'fs.readFile'
  | 'fs.listDir'
  | 'fs.makeDir'
  | 'fs.deleteEntry'
  | 'fs.stat'
  | 'storage.get'
  | 'storage.set'
  | 'storage.remove'
  | 'storage.list'
  | 'settings.get'
  | 'settings.getMany'
  | 'calendar.getSelectedDate'
  | 'calendar.getDailyTimes'
  | 'calendar.getHalachicTimes'
  | 'calendar.getCities'
  | 'calendar.getJewishDate'
  | 'calendar.getEvents'
  | 'publishedData.upsert'
  | 'publishedData.remove'
  | 'publishedData.listOwn'
  | 'feedback.sendEmail'
  | 'feedback.report'
  | 'feedback.hasReporterEmail'
  | 'history.list'
  | 'history.listSearches'
  | 'history.clear'
  | 'history.remove'
  | 'bookmarks.list'
  | 'bookmarks.add'
  | 'bookmarks.remove'
  | 'tools.gematria'
  | 'tools.dictionary'
  | 'notifications.showInApp'
  | 'notifications.sendSystem'
  | 'notifications.scheduleSystem'
  | 'notifications.cancel'
  | 'notifications.cancelAll'
  | 'notifications.checkPermissions'
  | 'notifications.requestPermissions'
  | 'database.listSources'
  | 'database.describeSource'
  | 'database.query'
  | 'database.batchQuery'
  | 'network.fetch'
  | 'network.fetchStream'
  | 'network.download'
  | 'fs.pickUserFile'
  | 'fs.resolveFileUrl'
  | 'fs.readTextFile'
  | 'fs.revokeFile'
  | 'fs.beginBinaryWrite'
  | 'fs.commitUserFileWrite'
  | 'fs.abortBinaryWrite'
  | 'fs.extractZip'
  | 'fs.deleteFile'
  | 'shortcut.create'
  | 'plugin.openSelf'
  | 'plugin.openOther'
  /** @internal חנות התוספים בלבד — לא מתועד ב-API_REFERENCE ואינו חוזה יציב. */
  | 'plugin.requestInstall'
  | 'plugin.backgroundDone'
  | 'plugin.listInstalled'
  | 'reader.addContextMenuItem'
  | 'reader.removeContextMenuItem'
  | 'reader.updateContextMenuItem'
  | 'reader.addToolbarItem'
  | 'reader.removeToolbarItem'
  | 'reader.updateToolbarItem'
  | 'reader.setHighlight'
  | 'reader.updateHighlight'
  | 'reader.getHighlights'
  | 'reader.revealHighlight'
  | 'reader.clearHighlight'
  | 'reader.clearAllHighlights';

// ---------------------------------------------------------------------------
// The global Otzaria object
// ---------------------------------------------------------------------------

export interface OtzariaGlobal {
  /** חיפוש מלא שמזרים chunks ככל שהם מתקבלים מהמנוע. */
  call(
    method: 'search.query',
    payload: SearchQueryParams
  ): AsyncIterable<SearchQueryChunk>;

  /** בקשת HTTP שמזרימה כותרות ומקטעי גוף עם הגעתם. */
  call(
    method: 'network.fetchStream',
    payload: NetworkFetchParams
  ): AsyncIterable<NetworkFetchStreamChunk>;

  /** פותח כרטיסיית חיפוש מובנית עם השאילתה וההגדרות. */
  call(
    method: 'reader.openSearchTab',
    payload: OpenSearchTabArgs
  ): Promise<OtzariaResponse<boolean>>;

  /** מחזיר רשימה של כל התוספים המותקנים. */
  call(
    method: 'plugin.listInstalled',
    payload?: Record<string, unknown>
  ): Promise<OtzariaResponse<InstalledPlugin[]>>;

  /**
   * Call a Host API method.
   *
   * @param method  Dot-separated, e.g. `'library.findBooks'`
   * @param payload Method arguments
   */
  call<T = unknown>(
    method: OtzariaMethod | string,
    payload?: Record<string, unknown>
  ): Promise<OtzariaResponse<T>>;

  /** Subscribe to a host-dispatched event. */
  on<K extends keyof OtzariaEventMap>(
    event: K,
    callback: (detail: OtzariaEventMap[K]) => void
  ): void;
  on(event: string, callback: (detail: unknown) => void): void;

  /** Unsubscribe. Must use the exact same function reference passed to `on()`. */
  off<K extends keyof OtzariaEventMap>(
    event: K,
    callback: (detail: OtzariaEventMap[K]) => void
  ): void;
  off(event: string, callback: (detail: unknown) => void): void;

  /**
   * Turns bare `otzaria://` URLs inside `root` (default: `document.body`) into
   * clickable anchors. Returns the number of text nodes replaced.
   *
   * Skips `<a>`, `<code>`, `<pre>`, `<textarea>`, `<input>`, `<script>`,
   * contenteditable subtrees and anything under `[data-otzaria-no-linkify]`.
   * Set `contributes.autoLinkify` in the manifest to run it automatically.
   */
  linkify(root?: Element | Document): number;
}

// ---------------------------------------------------------------------------
// Augment global Window
// ---------------------------------------------------------------------------

declare global {
  interface Window {
    /** Injected automatically into every plugin WebView. */
    Otzaria: OtzariaGlobal;
  }
  const Otzaria: OtzariaGlobal;
}

export {};
