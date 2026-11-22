// גלריית העיצוב: התצוגה החיה של הרכיבים, ומטריצה של ערכות נושא x רוחבים.
// ה-API שבשימוש: plugin.boot, theme.changed, plugin.resumed, app.getTheme,
// ui.showMessage/showSuccess/showError/showConfirm, ui.setFullscreen,
// ui.fullscreenChanged, storage.get/set. אין הרשאה להצהיר: כולן הרשאות בסיס או ללא הרשאה.
(function () {
  'use strict';

  const hasHost = typeof Otzaria !== 'undefined';
  const THEMES = window.GALLERY_THEMES || [];
  const WIDTHS = [320, 360, 480, 600, 840, 1000, 1200];
  const STORAGE_KEY = 'design-gallery.state';

  const BOOKS = [
    { title: 'בראשית', ref: 'פרק א, פסוק ה', group: 'tanakh', text: 'ויהי ערב ויהי בקר יום אחד.' },
    { title: 'תהילים', ref: 'פרק א, פסוק א', group: 'tanakh', text: 'אשרי האיש אשר לא הלך בעצת רשעים.' },
    { title: 'משלי', ref: 'פרק ט, פסוק א', group: 'tanakh', text: 'חכמות בנתה ביתה, חצבה עמודיה שבעה.' },
    { title: 'ברכות', ref: 'דף ב עמוד א', group: 'mishna', text: 'מאימתי קורין את שמע בערבין, משעה שהכהנים נכנסים לאכול בתרומתן.' },
    { title: 'פרקי אבות', ref: 'פרק א, משנה א', group: 'mishna', text: 'משה קבל תורה מסיני ומסרה ליהושע, ויהושע לזקנים.' },
    { title: 'שבת', ref: 'דף ב עמוד א', group: 'mishna', text: 'יציאות השבת שתים שהן ארבע בפנים ושתים שהן ארבע בחוץ.' },
    { title: 'הלכות תפילה', ref: 'פרק א, הלכה א', group: 'halacha', text: 'מצות עשה להתפלל בכל יום, בלשון הקודש או בכל לשון שהוא מבין.' },
    { title: 'הלכות שבת', ref: 'פרק א, הלכה א', group: 'halacha', text: 'ארבעה ועשרים דברים אסורין בשבת.' },
  ];

  const state = {
    view: 'live',
    themes: ['live', 'dark-default'],
    widths: [360, 600, 1000],
    filter: 'all',
    demo: 'results',
    query: '',
  };
  let liveTheme = null; // ה-payload האחרון שהגיע מאוצריא
  let appVersion = '';
  let searchTimer = 0;

  const $ = (root, selector) => root.querySelector(selector);
  const $$ = (root, selector) => Array.from(root.querySelectorAll(selector));

  function make(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function icon(name, className) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', className || 'icon');
    svg.setAttribute('aria-hidden', 'true');
    const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', '#i-' + name);
    svg.appendChild(use);
    return svg;
  }

  // ── ערכת נושא ──────────────────────────────────────────────────────────

  function updateHostInfo() {
    const info = $(document, '[data-host-info]');
    if (!liveTheme) return;
    const mode = liveTheme.mode === 'dark' ? 'כהה' : 'בהיר';
    const density = liveTheme.density
      ? liveTheme.density.compact ? 'מצומצמת' : 'רגילה'
      : 'לא נשלחה (מארח ישן)';
    const version = appVersion ? ' · אוצריא ' + appVersion : ' · מצב עצמאי';
    info.textContent = 'מצב ' + mode + ' · צפיפות ' + density + version;
  }

  function onTheme(theme) {
    if (!theme || !theme.colorScheme || !theme.colorScheme.primary) return;
    liveTheme = theme;
    window.applyTheme(theme);
    fillFontInfo($(document, '[data-live-root]'), document.documentElement);
    updateHostInfo();
    if (state.view === 'matrix') {
      renderMatrixControls();
      renderMatrix();
    }
  }

  function fillFontInfo(root, scope) {
    const target = $(root, '[data-font-ui]');
    if (target) {
      target.textContent = getComputedStyle(scope).getPropertyValue('--font-ui').split(',')[0].trim();
    }
  }

  // ── מצב שנשמר ──────────────────────────────────────────────────────────

  function saveState() {
    if (!hasHost) return;
    Otzaria.call('storage.set', {
      key: STORAGE_KEY,
      value: { view: state.view, themes: state.themes, widths: state.widths },
    });
  }

  function restoreState() {
    if (!hasHost) return Promise.resolve();
    return Otzaria.call('storage.get', { key: STORAGE_KEY }).then((res) => {
      const saved = res && res.success ? res.data : null;
      if (!saved) return;
      if (saved.view === 'live' || saved.view === 'matrix') state.view = saved.view;
      if (Array.isArray(saved.themes)) state.themes = saved.themes;
      if (Array.isArray(saved.widths)) state.widths = saved.widths.filter((w) => WIDTHS.includes(w));
      renderMatrixControls();
      setView(state.view, false);
    });
  }

  // ── הודעות של המארח ────────────────────────────────────────────────────

  function showHostBanner(kind, title, text) {
    const slot = $(document, '[data-host-banner]');
    slot.replaceChildren();
    const banner = make('div', 'banner' + (kind === 'info' ? '' : ' banner-' + kind));
    banner.setAttribute('role', kind === 'error' ? 'alert' : 'status');
    banner.appendChild(icon(kind === 'info' ? 'info' : kind === 'success' ? 'check' : kind));
    const body = make('div', 'banner-text');
    body.appendChild(make('p', 'banner-title', title));
    body.appendChild(make('p', 'banner-body', text));
    banner.appendChild(body);
    const close = make('button', 'btn btn-icon');
    close.type = 'button';
    close.setAttribute('aria-label', 'סגור הודעה');
    close.appendChild(icon('close'));
    close.addEventListener('click', () => slot.replaceChildren());
    banner.appendChild(close);
    slot.appendChild(banner);
  }

  function hostMissing(what) {
    showHostBanner('info', 'מצב עצמאי', what + ' זמין רק בתוך אוצריא.');
  }

  function toast(kind, message) {
    if (!hasHost) return hostMissing('ההודעה');
    if (kind === 'success') return Otzaria.call('ui.showSuccess', { message });
    if (kind === 'error') return Otzaria.call('ui.showError', { message });
    return Otzaria.call('ui.showMessage', { message });
  }

  function confirmHost() {
    if (!hasHost) return hostMissing('הדיאלוג');
    return Otzaria.call('ui.showConfirm', {
      title: 'אישור מוצג על ידי אוצריא',
      content: 'הדיאלוג הזה אינו נצבע על ידי התוסף. האם להמשיך?',
    }).then((res) => {
      if (!res.success) return showHostBanner('error', 'הדיאלוג נכשל', res.error.code);
      showHostBanner('info', 'תשובת המשתמש', res.data.confirmed ? 'אושר' : 'בוטל');
    });
  }

  // המצב האמיתי מגיע מ-ui.fullscreenChanged ולא מהלחיצה: Escape ו-F11 יוצאים
  // ממסך מלא בלי לשאול את התוסף. הדף נפתח במצב רגיל.
  let isFullscreen = false;
  const fullscreenButton = $(document, '[data-action="fullscreen"]');

  function onFullscreenChanged(event) {
    isFullscreen = event.fullscreen;
    const label = isFullscreen ? 'יציאה ממסך מלא' : 'מסך מלא';
    fullscreenButton.setAttribute('aria-label', label);
    fullscreenButton.setAttribute('title', label);
    fullscreenButton.setAttribute('aria-pressed', String(isFullscreen));
  }

  // כניסה חייבת להיקרא ישירות מ-click: אוצריא מחזירה error.forbidden לקריאה
  // שאינה פעולת משתמש. אין await לפניה.
  function toggleFullscreen() {
    if (!hasHost) return hostMissing('מסך מלא');
    return Otzaria.call('ui.setFullscreen', { fullscreen: !isFullscreen }).then((res) => {
      if (res.success) return;
      showHostBanner('warning', 'מסך מלא אינו זמין', res.error.code + ': ' + res.error.message);
    });
  }

  // ── תוצאות ומצבי טעינה, ריק ושגיאה ─────────────────────────────────────

  function highlighted(text, query) {
    const p = make('p', 'excerpt selectable');
    const index = query ? text.indexOf(query) : -1;
    if (index < 0) {
      p.textContent = text;
      return p;
    }
    p.appendChild(document.createTextNode(text.slice(0, index)));
    p.appendChild(make('mark', '', query));
    p.appendChild(document.createTextNode(text.slice(index + query.length)));
    return p;
  }

  function resultCard(book, rank, query) {
    const card = make('article', 'card card-interactive result');
    card.tabIndex = 0;
    card.setAttribute('aria-selected', 'false');
    card.appendChild(make('span', 'result-rank', String(rank)));
    const body = make('div');
    body.appendChild(make('h3', 'card-title', book.title));
    body.appendChild(make('p', 'card-meta', book.ref));
    body.appendChild(highlighted(book.text, query));
    const tags = make('div', 'row');
    tags.appendChild(make('span', 'chip', book.group === 'tanakh' ? 'תנ"ך' : book.group === 'mishna' ? 'משנה ותלמוד' : 'הלכה'));
    body.appendChild(tags);
    card.appendChild(body);
    const actions = make('div', 'result-actions');
    const open = make('button', 'btn btn-primary', 'פתח');
    open.type = 'button';
    open.dataset.action = 'open-book';
    open.dataset.title = book.title;
    const add = make('button', 'btn btn-ghost', 'הוסף לרשימה');
    add.type = 'button';
    add.dataset.action = 'add-to-list';
    actions.append(open, add);
    card.appendChild(actions);
    return card;
  }

  function stateBlock(kind, title, body, actionLabel, actionName) {
    const block = make('div', 'state' + (kind === 'error' ? ' state-error' : ''));
    block.setAttribute('role', kind === 'error' ? 'alert' : 'status');
    block.appendChild(icon(kind === 'error' ? 'error' : 'search', 'icon icon-lg'));
    block.appendChild(make('p', 'state-title', title));
    block.appendChild(make('p', 'state-body', body));
    if (actionLabel) {
      const button = make('button', 'btn' + (kind === 'error' ? ' btn-primary' : ''), actionLabel);
      button.type = 'button';
      button.dataset.action = actionName;
      block.appendChild(button);
    }
    return block;
  }

  function loadingBlock() {
    const wrap = make('div', 'results');
    wrap.setAttribute('aria-busy', 'true');
    for (let i = 0; i < 2; i++) {
      const card = make('div', 'card');
      [90, 60, 75].forEach((width) => {
        const line = make('div', 'skeleton-line');
        line.style.width = width + '%';
        card.appendChild(line);
      });
      wrap.appendChild(card);
    }
    return wrap;
  }

  function renderResults(root, options) {
    const results = $(root, '[data-results]');
    const count = $(root, '[data-result-count]');
    results.replaceChildren();
    if (options.demo === 'loading') {
      count.textContent = 'טוען…';
      results.appendChild(loadingBlock());
      return;
    }
    if (options.demo === 'error') {
      count.textContent = 'שגיאה';
      results.appendChild(stateBlock('error', 'הטעינה נכשלה', 'לא הצלחנו לטעון את התוצאות. אפשר לנסות שוב.', 'נסה שוב', 'retry'));
      return;
    }
    const matches = options.demo === 'empty'
      ? []
      : BOOKS.filter((book) =>
          (options.filter === 'all' || book.group === options.filter) &&
          (!options.query || (book.title + ' ' + book.text).includes(options.query)));
    count.textContent = matches.length + ' תוצאות';
    if (!matches.length) {
      results.appendChild(stateBlock('empty', 'לא נמצאו תוצאות', 'נסו מילה אחרת או הסירו את הסינון.', options.query ? 'נקה חיפוש' : '', 'clear-search'));
      return;
    }
    const grid = make('div', 'results');
    matches.slice(0, options.limit || matches.length).forEach((book, i) => grid.appendChild(resultCard(book, i + 1, options.query)));
    results.appendChild(grid);
  }

  function liveRoot() {
    return $(document, '[data-live-root]');
  }

  function refreshLiveResults() {
    window.clearTimeout(searchTimer);
    const root = liveRoot();
    if (state.demo !== 'results' || !state.query) {
      renderResults(root, state);
      return;
    }
    // חיפוש אמיתי לוקח זמן: מציגים טעינה ואז את התוצאות.
    renderResults(root, { demo: 'loading' });
    searchTimer = window.setTimeout(() => renderResults(root, state), 350);
  }

  // ── תצוגה חיה ──────────────────────────────────────────────────────────

  function mountLive() {
    const root = liveRoot();
    root.appendChild(document.getElementById('components').content.cloneNode(true));
    renderResults(root, state);
    fillFontInfo(root, document.documentElement);
    bindLive(root);
  }

  function closeMenus() {
    $$(document, '[data-menu]').forEach((menu) => {
      menu.hidden = true;
      const trigger = menu.parentElement.querySelector('[data-action="toggle-menu"]');
      if (trigger) trigger.setAttribute('aria-expanded', 'false');
    });
  }

  function openPanel(open) {
    $(document, '[data-side-panel]').classList.toggle('open', open);
    $(document, '[data-scrim]').classList.toggle('open', open);
    if (open) $(document, '[data-side-panel] button').focus();
  }

  function bindLive(root) {
    const input = $(root, '[data-search-input]');
    const clear = $(root, '[data-search-clear]');

    input.addEventListener('input', () => {
      state.query = input.value.trim();
      clear.hidden = !input.value;
      refreshLiveResults();
    });

    $$(root, '[data-demo-input]').forEach((field) => {
      const help = field.parentElement.querySelector('.field-help');
      field.addEventListener('input', () => {
        const tooLong = field.value.length > 40;
        field.setAttribute('aria-invalid', String(tooLong));
        help.className = tooLong ? 'field-error' : 'field-help';
        help.textContent = tooLong ? 'יותר מ-40 תווים.' : 'עד 40 תווים.';
      });
    });

    root.addEventListener('click', (event) => {
      const target = event.target.closest('[data-action], [data-filter], [data-demo-state], [data-search-clear], [data-selectable], .card-interactive');
      if (!target || !root.contains(target)) return;

      if (target.matches('[data-search-clear]') || target.dataset.action === 'clear-search') {
        input.value = '';
        state.query = '';
        clear.hidden = true;
        refreshLiveResults();
        input.focus();
      } else if (target.dataset.filter) {
        state.filter = target.dataset.filter;
        $$(root, '[data-filter]').forEach((chip) => chip.setAttribute('aria-pressed', String(chip === target)));
        refreshLiveResults();
      } else if (target.dataset.demoState) {
        state.demo = target.dataset.demoState;
        $$(root, '[data-demo-state]').forEach((b) => b.setAttribute('aria-pressed', String(b === target)));
        refreshLiveResults();
      } else if (target.dataset.action) {
        runAction(target.dataset.action, target);
      } else if (target.matches('[data-selectable], .card-interactive')) {
        const selected = target.getAttribute('aria-selected') === 'true';
        target.setAttribute('aria-selected', String(!selected));
      }
      if (!target.closest('.popover-anchor')) closeMenus();
    });

    root.addEventListener('keydown', (event) => {
      const row = event.target.closest('[data-selectable], .card-interactive');
      if (row && event.target === row && (event.key === 'Enter' || event.key === ' ')) {
        event.preventDefault();
        row.click();
      }
    });
  }

  function runAction(name, target) {
    switch (name) {
      case 'retry':
        state.demo = 'results';
        $$(liveRoot(), '[data-demo-state]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.demoState === 'results')));
        refreshLiveResults();
        break;
      case 'open-book':
        toast('info', 'פתיחת "' + target.dataset.title + '" (הדגמה)');
        break;
      case 'add-to-list':
        toast('success', 'נוסף לרשימה (הדגמה)');
        break;
      case 'snack-info': toast('info', 'זו הודעה רגילה של אוצריא'); break;
      case 'snack-success': toast('success', 'הפעולה הושלמה'); break;
      case 'snack-error': toast('error', 'הפעולה נכשלה'); break;
      case 'confirm-host': confirmHost(); break;
      case 'open-dialog': $(document, '[data-dialog]').showModal(); break;
      case 'open-panel': openPanel(true); break;
      case 'toggle-menu': {
        const menu = target.parentElement.querySelector('[data-menu]');
        const willOpen = menu.hidden;
        closeMenus();
        menu.hidden = !willOpen;
        target.setAttribute('aria-expanded', String(willOpen));
        if (willOpen) menu.querySelector('.menu-item').focus();
        break;
      }
      case 'busy-demo': {
        target.setAttribute('aria-busy', 'true');
        $(target, '.spinner').hidden = false;
        window.setTimeout(() => {
          target.removeAttribute('aria-busy');
          $(target, '.spinner').hidden = true;
        }, 1200);
        break;
      }
      default:
    }
  }

  // ── מטריצה ─────────────────────────────────────────────────────────────

  function themeOptions() {
    const options = THEMES.map((t) => ({ id: t.id, label: t.label, theme: t.theme }));
    if (liveTheme) options.unshift({ id: 'live', label: 'הערכה החיה (מאוצריא)', theme: liveTheme });
    return options;
  }

  function chip(label, pressed, onToggle) {
    const button = make('button', 'chip chip-filter');
    button.type = 'button';
    button.setAttribute('aria-pressed', String(pressed));
    const check = icon('check', 'icon icon-check');
    button.append(check, document.createTextNode(label));
    button.addEventListener('click', () => {
      const next = button.getAttribute('aria-pressed') !== 'true';
      button.setAttribute('aria-pressed', String(next));
      onToggle(next);
    });
    return button;
  }

  function toggleIn(list, value, on) {
    const without = list.filter((item) => item !== value);
    return on ? without.concat(value) : without;
  }

  function renderMatrixControls() {
    const themes = $(document, '[data-matrix-themes]');
    const widths = $(document, '[data-matrix-widths]');
    themes.replaceChildren();
    widths.replaceChildren();
    themeOptions().forEach((option) => {
      themes.appendChild(chip(option.label, state.themes.includes(option.id), (on) => {
        state.themes = toggleIn(state.themes, option.id, on);
        renderMatrix();
        saveState();
      }));
    });
    WIDTHS.forEach((width) => {
      widths.appendChild(chip(width + 'px', state.widths.includes(width), (on) => {
        state.widths = toggleIn(state.widths, width, on);
        renderMatrix();
        saveState();
      }));
    });
  }

  function buildFrame(option, width) {
    const frame = make('div', 'frame theme-scope');
    frame.style.width = width + 'px';
    window.applyTheme(option.theme, frame);
    frame.appendChild(make('div', 'frame-caption', width + 'px · ' + option.label));
    const body = make('div', 'frame-body');
    body.appendChild(document.getElementById('frame-topbar').content.cloneNode(true));
    const content = make('div', 'frame-content sections');
    content.appendChild(document.getElementById('components').content.cloneNode(true));
    body.appendChild(content);
    frame.appendChild(body);
    renderResults(content, { demo: 'results', filter: 'all', query: '', limit: 2 });
    fillFontInfo(content, frame);
    return frame;
  }

  function renderMatrix() {
    const root = $(document, '[data-matrix-root]');
    root.replaceChildren();
    const selected = themeOptions().filter((option) => state.themes.includes(option.id));
    if (!selected.length || !state.widths.length) {
      root.appendChild(stateBlock('empty', 'לא נבחרו ערכות או רוחבים', 'בחרו לפחות ערכה אחת ורוחב אחד.', '', ''));
      return;
    }
    selected.forEach((option) => {
      const group = make('div');
      group.appendChild(make('h3', 'matrix-group-title', option.label));
      const row = make('div', 'frame-row');
      state.widths.slice().sort((a, b) => a - b).forEach((width) => row.appendChild(buildFrame(option, width)));
      group.appendChild(row);
      root.appendChild(group);
    });
  }

  function setView(view, persist) {
    state.view = view;
    $$(document, '[data-view-panel]').forEach((panel) => { panel.hidden = panel.dataset.viewPanel !== view; });
    $$(document, '[data-view]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.view === view)));
    if (view === 'matrix') {
      renderMatrixControls();
      renderMatrix();
    }
    if (persist !== false) saveState();
  }

  // ── חיבורים כלליים ─────────────────────────────────────────────────────

  $$(document, '[data-view]').forEach((button) => {
    button.addEventListener('click', () => setView(button.dataset.view));
  });
  fullscreenButton.addEventListener('click', toggleFullscreen);
  $(document, '[data-scrim]').addEventListener('click', () => openPanel(false));
  $$(document, '[data-action="close-panel"]').forEach((b) => b.addEventListener('click', () => openPanel(false)));
  $$(document, '[data-action="close-dialog"]').forEach((b) => b.addEventListener('click', () => $(document, '[data-dialog]').close()));
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    openPanel(false);
    closeMenus();
  });
  document.addEventListener('click', (event) => {
    if (!event.target.closest('.popover-anchor')) closeMenus();
  });

  mountLive();
  $(liveRoot(), '[data-search-input]').focus();
  // קישור ישיר למטריצה בדפדפן רגיל: index.html#matrix
  if (window.location.hash === '#matrix') setView('matrix', false);

  if (hasHost) {
    Otzaria.on('plugin.boot', (payload) => {
      appVersion = payload.app && payload.app.version ? payload.app.version : '';
      onTheme(payload.theme);
      restoreState();
    });
    Otzaria.on('theme.changed', onTheme);
    Otzaria.on('ui.fullscreenChanged', onFullscreenChanged);
    // בזמן השהיה אוצריא שומרת רק את ה-theme.changed האחרון; לא לסמוך עליו, לשאול מחדש.
    Otzaria.on('plugin.resumed', () => {
      Otzaria.call('app.getTheme').then((res) => {
        if (res.success) onTheme(res.data);
      });
    });
  } else if (THEMES.length) {
    onTheme(THEMES[0].theme);
    showHostBanner('info', 'מצב עצמאי', 'הדף נפתח מחוץ לאוצריא: הערכה היא הערכה הראשונה מבין הדוגמאות, וההודעות של אוצריא אינן זמינות.');
  }
})();
