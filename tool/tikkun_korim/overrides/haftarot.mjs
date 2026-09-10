// תיקוני נתוני ההפטרות מעל הייבוא מ-hebcal (דרך התוסף המקורי).
// כל שינוי כאן חייב מקור הלכתי — ראה את הבדיקות ב-test/tools/tikkun_korim/data/.

/// פרשות מחוברות: ההפטרה היא של הפרשה השנייה (שו"ע או"ח רפד ס"ז),
/// למעט אחרי-מות-קדושים שכבר קיים בנתוני המקור כחריג (רמ"א תכח ס"ח).
/// נצבים-וילך יוצאת מן הכלל: כלל "מפטירין באחרונה" נאמר בשאר שבתות השנה
/// (שו"ע תכח ס"ח), והיא לעולם השבת שלפני ר"ה — השביעית דנחמתא, "שוש אשיש".
const COMBINED = [
  { id: 'p:Vayakhel-Pekudei', name: 'ויקהל-פקודי', from: 'p:Pekudei', after: 'p:Pekudei' },
  { id: 'p:Tazria-Metzora', name: 'תזריע-מצורע', from: 'p:Metzora', after: 'p:Metzora' },
  { id: 'p:Behar-Bechukotai', name: 'בהר-בחוקותי', from: 'p:Bechukotai', after: 'p:Bechukotai' },
  { id: 'p:Chukat-Balak', name: 'חקת-בלק', from: 'p:Balak', after: 'p:Balak' },
  { id: 'p:Matot-Masei', name: 'מטות-מסעי', from: 'p:Masei', after: 'p:Masei' },
  { id: 'p:Nitzavim-Vayeilech', name: 'נצבים-וילך', from: 'p:Nitzavim', after: 'p:Vayeilech' },
];

/// ערכים שנקראים בחוץ לארץ בלבד (יום טוב שני של גלויות),
/// ומסעי בשבת ר"ח — "שמעו" הוא מנהג אשכנזי חו"ל (רמ"א תכה,א).
const DIASPORA_ONLY = [
  'h:Pesach II',
  'h:Pesach VIII',
  'h:Shavuot II',
  'h:Sukkot II',
  'h:Shmini Atzeret',
  'h:Masei on Shabbat Rosh Chodesh',
];

/// ערכים שנקראים בארץ ישראל בלבד.
const ISRAEL_ONLY = ['h:Masei on Shabbat Rosh Chodesh (Israel)'];

/// ערכים כפולים במקור: זהים לחלוטין לערך אחר ברשימה.
const DROP = ['h:Shavuot', 'h:Yom Kippur (Mincha, Alternate)', 'h:Shabbat Shuva'];

const r = (book, from, to) => ({ book, from, to });

const same = (a, b) =>
  Array.isArray(a) &&
  Array.isArray(b) &&
  a.length === b.length &&
  a.every((x, i) => x.book === b[i].book && x.from === b[i].from && x.to === b[i].to);

const find = (list, id) => list.find((h) => h.id === id);

export function applyHaftarotOverrides(source) {
  const list = structuredClone(source);

  for (const id of DROP) {
    const i = list.findIndex((h) => h.id === id);
    if (i < 0) throw new Error(`haftarot override: missing ${id}`);
    list.splice(i, 1);
  }

  // מנחת יום כיפור — ההבדל בין שני הערכים שבמקור הוא בקריאת התורה בלבד.
  const ykMincha = find(list, 'h:Yom Kippur (Mincha, Traditional)');
  ykMincha.id = 'h:Yom Kippur (Mincha)';
  ykMincha.name = 'יום כיפור - מנחה';

  addCombined(list);
  addTishaBavMincha(list);
  addRepeatedVerses(list);
  addSimchatTorahSephard(list);
  addRoshChodeshVariants(list);
  markFastDayMincha(list);
  markLand(list);
  annotateKedoshim(list);
  dropMirroredSephard(list);
  return list;
}

function addCombined(list) {
  for (const c of COMBINED) {
    const src = find(list, c.from);
    if (!src) throw new Error(`haftarot override: missing ${c.from}`);
    const at = list.findIndex((h) => h.id === c.after);
    list.splice(at + 1, 0, {
      id: c.id,
      category: 'parasha',
      name: c.name,
      ashkenaz: structuredClone(src.ashkenaz),
      sephard: structuredClone(src.sephard),
    });
  }
}

/// ט' באב מנחה: אשכנז "דרשו"; ספרדים "שובה ישראל" (הושע יד + מיכה ז).
function addTishaBavMincha(list) {
  const at = list.findIndex((h) => h.id === "h:Tish'a B'Av");
  if (at < 0) throw new Error("haftarot override: missing h:Tish'a B'Av");
  list.splice(at + 1, 0, {
    id: "h:Tish'a B'Av (Mincha)",
    category: 'special',
    name: 'תשעה באב - מנחה',
    ashkenaz: [r('ישעיהו', '55:6', '56:8')],
    sephard: [r('הושע', '14:2', '14:10'), r('מיכה', '7:18', '7:20')],
  });
}

/// חוזרים על הפסוק הלפני-אחרון בסוף ישעיהו ובסוף מלאכי.
function addRepeatedVerses(list) {
  const rc = find(list, 'h:Shabbat Rosh Chodesh');
  const gadol = find(list, 'h:Shabbat HaGadol');
  for (const seg of [rc.ashkenaz, rc.sephard]) seg.push(r('ישעיהו', '66:23', '66:23'));
  for (const seg of [gadol.ashkenaz, gadol.sephard]) seg.push(r('מלאכי', '3:23', '3:23'));
}

/// מנחת תענית ציבור: רק אשכנזים מפטירים "דרשו"; לספרדים אין הפטרה.
function markFastDayMincha(list) {
  find(list, 'h:Fast Day (Afternoon)').sephardNone = true;
}

/// שמחת תורה: ספרדים מסיימים ביהושע א, ט (שו"ע תרסח ס"ב), כבוזאת הברכה.
function addSimchatTorahSephard(list) {
  const st = find(list, 'h:Simchat Torah');
  st.sephard = structuredClone(find(list, 'p:Vezot Haberakhah').sephard);
}

/// שבתות ר"ח שאינן בנתוני המקור, ומסעי בשבת ר"ח אב בארץ ישראל.
/// שו"ע ורמ"א תכה,א–ב; ביאור הגר"א שם.
function addRoshChodeshVariants(list) {
  const rc = find(list, 'h:Shabbat Rosh Chodesh');
  const masei = find(list, 'h:Masei on Shabbat Rosh Chodesh');
  const at = list.findIndex((h) => h.id === 'h:Shabbat Rosh Chodesh');

  list.splice(at + 1, 0, {
    id: 'h:Shabbat Rosh Chodesh Elul',
    category: 'special',
    name: 'שבת ראש חודש אלול',
    ashkenaz: structuredClone(rc.ashkenaz),
    sephard: [r('ישעיהו', '54:11', '55:5')],
  }, {
    id: 'h:Shabbat Rosh Chodesh (Machar Chodesh)',
    category: 'special',
    name: 'שבת ראש חודש שני ימים (שבת וראשון)',
    ashkenaz: structuredClone(rc.ashkenaz),
    sephard: [
      ...structuredClone(rc.ashkenaz),
      r('שמואל א', '20:18', '20:18'),
      r('שמואל א', '20:42', '20:42'),
    ],
  });

  const maseiAt = list.findIndex((h) => h.id === masei.id);
  list.splice(maseiAt + 1, 0, {
    id: 'h:Masei on Shabbat Rosh Chodesh (Israel)',
    category: 'special',
    name: masei.name,
    ashkenaz: structuredClone(rc.ashkenaz),
    sephard: structuredClone(masei.sephard),
  });
}

function markLand(list) {
  for (const h of list) {
    if (DIASPORA_ONLY.includes(h.id)) h.land = 'diaspora';
    else if (ISRAEL_ONLY.includes(h.id)) h.land = 'israel';
    else h.land = 'both';
  }
}

/// קדושים לאשכנז — יש המסיימים בכב, טז.
function annotateKedoshim(list) {
  find(list, 'p:Kedoshim').name = 'קדושים (יש הקוראים עד כב, טז)';
}

/// ב-hebcal `seph: null` פירושו "לא נבדק", והייבוא שכפל את אשכנז.
/// ריקון העמודה מונע ביטחון שווא; הפולבק ב-forNusach מחזיר אשכנז.
function dropMirroredSephard(list) {
  for (const h of list) {
    if (same(h.ashkenaz, h.sephard)) h.sephard = [];
  }
}
