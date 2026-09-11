// תיקוני נתוני קריאות המועדים מעל טבלת התוסף המקורי.
// כל תיקון מסומן במקורו ההלכתי; ראה applyReadingsOverrides בתחתית הקובץ.

const LABELS = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'ששי', 'שביעי', 'שמיני'];

/// עליה לפי מספר סידורי (1..8), עם התווית העברית הרגילה.
function ali(n, book, from, to) {
  return { aliya: String(n), aliyaLabel: LABELS[n - 1], book, from, to };
}

/// עליה עם תווית מפורשת (מפטיר, חתן תורה וכדומה).
function named(aliya, aliyaLabel, book, from, to) {
  return { aliya, aliyaLabel, book, from, to };
}

const maftir = (book, from, to) => named('M', 'מפטיר', book, from, to);

function indexOfId(list, id) {
  const i = list.findIndex((r) => r.id === id);
  if (i < 0) throw new Error(`readings override: id not found: ${id}`);
  return i;
}

function patch(list, id, fields) {
  list[indexOfId(list, id)] = { ...list[indexOfId(list, id)], ...fields };
}

function insertAfter(list, id, ...entries) {
  list.splice(indexOfId(list, id) + 1, 0, ...entries);
}

function replaceWith(list, id, ...entries) {
  list.splice(indexOfId(list, id), 1, ...entries);
}

/// שכפול ערך קיים עם מזהה, שם ושדות אחרים חדשים.
function clone(list, id, fields) {
  return { ...list[indexOfId(list, id)], ...fields };
}

const BM = 'במדבר';

// שו"ע או"ח תרפד,א: הקריאה מתחילה בברכת כהנים, והרמ"א ("וכן אנו נוהגין")
// מתחיל מ"ויהי ביום כלות משה". הערך הקיים הוא צורת הרמ"א.
function chanukahDay1(list) {
  patch(list, 'tr:Chanukah Day 1', { nusach: 'ashkenaz' });
  insertAfter(list, 'tr:Chanukah Day 1', {
    id: 'custom:Chanukah Day 1 Sephard',
    category: 'chanukah',
    name: "חנוכה - יום א'",
    land: 'both',
    nusach: 'sephard',
    aliyot: [
      ali(1, BM, '6:22', '7:3'),
      ali(2, BM, '7:4', '7:11'),
      ali(3, BM, '7:12', '7:17'),
    ],
  });
}

// יום ו' של חנוכה הוא תמיד ר"ח טבת — ג' עולים בשל ר"ח ורביעי בשל חנוכה
// (שו"ע או"ח תרפד,ג; מ"ב שם ס"ק יב). הערך לא"י נשמט מכך.
function chanukahDay6Israel(list) {
  patch(list, 'custom:Chanukah Day 6 IL', {
    aliyot: [
      ali(1, BM, '28:1', '28:5'),
      ali(2, BM, '28:6', '28:10'),
      ali(3, BM, '28:11', '28:15'),
      ali(4, BM, '7:42', '7:47'),
    ],
  });
}

// מ"ב תרפד ס"ק ו: כשר"ח טבת שני ימים, בשבת שהיא יום ז' דחנוכה
// המפטיר קורא את נשיא היום השביעי.
function shabbatRoshChodeshChanukah(list) {
  patch(list, 'tr:Shabbat Rosh Chodesh Chanukah', {
    name: "שבת ראש חודש חנוכה (יום ו' דחנוכה)",
  });
  insertAfter(
    list,
    'tr:Shabbat Rosh Chodesh Chanukah',
    clone(list, 'tr:Shabbat Rosh Chodesh Chanukah', {
      id: 'custom:Shabbat Rosh Chodesh Chanukah Day 7',
      name: "שבת ראש חודש חנוכה (יום ז' דחנוכה)",
      aliyot: [
        named('7', 'שביעי', BM, '28:9', '28:15'),
        maftir(BM, '7:48', '7:53'),
      ],
    }),
  );
}

// קרבן מוסף של כל אחד מימי סוכות (במדבר כט), לפי יום החג.
const SUKKOT_KORBAN = {
  2: ['29:17', '29:19'],
  3: ['29:20', '29:22'],
  4: ['29:23', '29:25'],
  5: ['29:26', '29:28'],
  6: ['29:29', '29:31'],
  7: ['29:32', '29:34'],
};

// שבת חוה"מ סוכות יכולה לחול רק ביום ג', ה' או ו' דסוכות.
const SHABBAT_CHM_DAYS = [3, 5, 6];
const DAY_LETTER = { 3: "ג'", 5: "ה'", 6: "ו'" };

// בא"י המפטיר הוא קרבן היום; בחו"ל ספיקא דיומא — קרבן שני הימים.
// הערך המקורי `tr:Sukkot Shabbat Chol ha-Moed` כלל ז' עליות בלי מפטיר כלל.
function sukkotShabbatCholHaMoed(list) {
  const base = list[indexOfId(list, 'tr:Sukkot Shabbat Chol ha-Moed')];
  const entries = [];
  for (const day of SHABBAT_CHM_DAYS) {
    const [from, to] = SUKKOT_KORBAN[day];
    const [prevFrom] = SUKKOT_KORBAN[day - 1];
    const label = `סוכות - שבת חוה"מ (יום ${DAY_LETTER[day]} דסוכות)`;
    entries.push(
      {
        ...base,
        id: `custom:Sukkot Shabbat CHM Day ${day} IL`,
        name: label,
        land: 'israel',
        aliyot: [...base.aliyot, maftir(BM, from, to)],
      },
      {
        ...base,
        id: `custom:Sukkot Shabbat CHM Day ${day}`,
        name: label,
        land: 'diaspora',
        aliyot: [...base.aliyot, maftir(BM, prevFrom, to)],
      },
    );
  }
  replaceWith(list, 'tr:Sukkot Shabbat Chol ha-Moed', ...entries);
}

// הושענא רבה: הערך הקיים הוא ספיקא דיומא של חו"ל; בא"י ארבעת העולים
// קוראים את קרבן היום השביעי (שו"ע או"ח קלז,ו — "חוץ מפרי החג").
function hoshanaRaba(list) {
  patch(list, 'tr:Sukkot Final Day (Hoshana Raba)', { land: 'diaspora' });
  const [from, to] = SUKKOT_KORBAN[7];
  insertAfter(list, 'tr:Sukkot Final Day (Hoshana Raba)', {
    id: 'custom:Hoshana Raba IL',
    category: 'sukkot',
    name: 'הושענא רבה',
    land: 'israel',
    aliyot: [1, 2, 3, 4].map((n) => ali(n, BM, from, to)),
  });
}

const DV = 'דברים';
const BR = 'בראשית';

/// החלפת תווית עליה קיימת לפי מספרה.
function relabel(list, id, aliya, aliyaLabel) {
  const entry = list[indexOfId(list, id)];
  entry.aliyot = entry.aliyot.map((a) => (a.aliya === aliya ? { ...a, aliyaLabel } : a));
}

// שמחת תורה: לג,כז–לד,יב ובראשית א,א–ב,ג אינן עליות "ששי/שביעי" אלא
// חתן תורה וחתן בראשית; לנוסח ספרדי "מעונה" (לג,כז–כט) הוא עליה בפני עצמה.
function simchatTorah(list) {
  for (const id of ['custom:Shmini Atzeret IL', 'tr:Simchat Torah']) {
    relabel(list, id, '6', 'חתן תורה');
    relabel(list, id, '7', 'חתן בראשית');
    patch(list, id, { nusach: 'ashkenaz' });
    const base = list[indexOfId(list, id)];
    insertAfter(list, id, {
      ...base,
      id: `${id} Sephard`,
      nusach: 'sephard',
      aliyot: [
        ...base.aliyot.slice(0, 5),
        named('6', 'חתן מעונה', DV, '33:27', '33:29'),
        named('7', 'חתן תורה', DV, '34:1', '34:12'),
        named('8', 'חתן בראשית', BR, '1:1', '2:3'),
        maftir(BM, '29:35', '30:1'),
      ],
    });
  }
  relabel(list, 'custom:Shmini Atzeret IL (on Shabbat)', '6', 'חתן מעונה');
  relabel(list, 'custom:Shmini Atzeret IL (on Shabbat)', '7', 'חתן תורה');
  relabel(list, 'custom:Shmini Atzeret IL (on Shabbat)', '8', 'חתן בראשית');
}

// מ"ב תכג ס"ק ג: לדעת הגר"א לוי קורא חמישה פסוקים עד סוף הפרשה,
// והשלישי חוזר על שלושת האחרונים.
function roshChodeshGra(list) {
  insertAfter(list, 'tr:Rosh Chodesh', {
    id: 'custom:Rosh Chodesh Gra',
    category: 'roshChodesh',
    name: 'ראש חודש (מנהג הגר"א)',
    land: 'both',
    aliyot: [
      ali(1, BM, '28:1', '28:3'),
      ali(2, BM, '28:4', '28:8'),
      ali(3, BM, '28:6', '28:10'),
      ali(4, BM, '28:11', '28:15'),
    ],
  });
}

/// מחיל את כל התיקונים על TORAH_READINGS_LIST ומחזיר רשימה חדשה.
export function applyReadingsOverrides(list) {
  const out = list.map((r) => ({ ...r, aliyot: [...r.aliyot] }));
  chanukahDay1(out);
  chanukahDay6Israel(out);
  shabbatRoshChodeshChanukah(out);
  sukkotShabbatCholHaMoed(out);
  hoshanaRaba(out);
  simchatTorah(out);
  roshChodeshGra(out);
  // קריאת המנחה בתענית ציבור זהה לשחרית; השם הקודם נראה כמחסור.
  patch(out, 'tr:Fast Day (Morning)', { name: 'תענית ציבור (שחרית ומנחה)' });
  return out;
}
