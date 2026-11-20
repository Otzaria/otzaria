// applyTheme: ממיר את ה-payload של ה-theme למשתני CSS.
// הקובץ הזה הוא המקור היחיד: DESIGN_GUIDE.md מצטט אותו מילה במילה, ובדיקת חוזה
// מוודאת שהשניים זהים ושכל שדה ב-payload נמצא בטבלת הטוקנים.
(function () {
  const applied = new WeakMap(); // אלמנט -> שמות המשתנים שהוצבו בו בפעם הקודמת

  // onSurfaceVariant -> on-surface-variant
  const kebab = (key) => key.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase());

  /**
   * target: האלמנט שמקבל את המשתנים. ברירת מחדל: כל הדף. בתצוגה של כמה ערכות
   * במקביל מוחלת ערכה על מסגרת, לא על :root.
   */
  window.applyTheme = function applyTheme(theme, target) {
    // מארח שהחלון שלו אינו מחובר מחזיר colorScheme ריק; אין מה להחיל.
    if (!theme || !theme.colorScheme || !theme.colorScheme.primary) return;
    const el = target || document.documentElement;
    const next = {};
    const set = (name, value) => {
      if (value !== undefined && value !== null && value !== '') {
        next[name] = String(value);
      }
    };

    const cs = theme.colorScheme;
    Object.keys(cs).forEach((key) => set('--color-' + kebab(key), cs[key]));

    // מ-0.9.99. במארח ישן השדות חסרים, והערכים נשארים אלה שב-:root.
    const s = theme.surfaces || {};
    set('--surface-reader', s.reader);
    set('--surface-panel', s.panel);
    set('--surface-card', s.card);
    set('--surface-top-bar', s.topBar);
    set('--surface-region-border', s.regionBorder);
    set('--surface-warning', s.warning);
    set('--surface-on-warning', s.onWarning);
    set('--surface-warning-container', s.warningContainer);
    set('--surface-on-warning-container', s.onWarningContainer);
    if (theme.radius != null) set('--radius', theme.radius + 'px');
    const spacing = theme.spacing || {};
    Object.keys(spacing).forEach((key) => set('--space-' + key, spacing[key] + 'px'));
    const d = theme.density || {};
    if (d.topBarHeight != null) set('--top-bar-height', d.topBarHeight + 'px');
    if (d.fieldHeight != null) set('--field-height', d.fieldHeight + 'px');

    const t = theme.typography || {};
    // גופן הממשק: uiFont (0.9.99) הוא מה שאוצריא מציירת; Rubik הוא fallback למארח ישן.
    if (t.uiFont) set('--font-ui', t.uiFont);
    else if (t.uiFontFamily) set('--font-ui', "'" + t.uiFontFamily + "', system-ui, sans-serif");
    // גופני הקריאה: רק לטקסט של ספרים, לא לממשק.
    if (t.fontFamily) set('--font-main', "'" + t.fontFamily + "', 'David', serif");
    if (t.commentatorsFontFamily) {
      set('--font-commentary', "'" + t.commentatorsFontFamily + "', 'David', serif");
    }
    if (t.fontSize) set('--font-size-reading', t.fontSize + 'px');
    if (t.commentatorsFontSize) set('--font-size-commentary', t.commentatorsFontSize + 'px');
    if (t.lineHeight) set('--line-height-reading', t.lineHeight);

    // משתנה שהוצב בפעם הקודמת ואינו ב-payload הנוכחי מוסר, כדי שלא יישאר ערך ישן.
    (applied.get(el) || []).forEach((name) => {
      if (!(name in next)) el.style.removeProperty(name);
    });
    Object.keys(next).forEach((name) => el.style.setProperty(name, next[name]));
    applied.set(el, Object.keys(next));

    // פקדים מקוריים (פסי גלילה, שדות) לפי מצב האפליקציה, לא לפי המערכת.
    el.style.colorScheme = theme.mode === 'dark' ? 'dark' : 'light';
    // למקרה נדיר שדרוש הבדל מבני בין מצבים (למשל וריאנט תמונה); לא לבחירת צבע.
    el.setAttribute('data-theme-mode', theme.mode === 'dark' ? 'dark' : 'light');
  };
})();
