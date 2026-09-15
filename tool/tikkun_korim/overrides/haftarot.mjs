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
  { id: 'p:Nitzavim-Vayeilech', name: 'נצבים-וילך', from: 'p:Nitzavim', after: 'p:Nitzavim' },
];

/// ערכים שנקראים בחוץ לארץ בלבד (יום טוב שני של גלויות).
const DIASPORA_ONLY = [
  'h:Pesach II',
  'h:Pesach VIII',
  'h:Shavuot II',
  'h:Sukkot II',
  'h:Shmini Atzeret',
];

/// ערכים שאינם נקראים בפועל, או זהים לערך אחר שנשאר ברשימה.
const DROP = [
  'h:Shavuot',
  'h:Yom Kippur (Mincha, Alternate)',
  // וילך לבדה חלה תמיד בשבת שובה; "דרשו" שבמקור הוא ערך תיאורטי.
  'p:Vayeilech',
  'h:Shabbat Shuva (with Vayeilech)',
  "h:Shabbat Shuva (with Ha'azinu)",
  'h:Kedoshim following Special Shabbat',
  'h:Pinchas occurring after 17 Tammuz',
  // שבת ר"ח אב היא תמיד מסעי, ומפטירים בה "שמעו" כבכל שנה.
  'h:Masei on Shabbat Rosh Chodesh',
  'h:Shabbat Rosh Chodesh Chanukah',
  'h:Chanukah Day 2 (on Shabbat)',
  'h:Chanukah Day 3 (on Shabbat)',
  'h:Chanukah Day 4 (on Shabbat)',
  'h:Chanukah Day 5 (on Shabbat)',
  'h:Chanukah Day 7 (on Shabbat)',
];

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

  fixShabbatShuva(list);
  mergeChanukah(list);
  renameThreeWeeks(list);
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

/// אשכנז: "שובה", "מי א-ל כמוך" ו"תקעו"; ספרדים: "שובה" ו"מי א-ל כמוך" בלבד.
function fixShabbatShuva(list) {
  find(list, 'h:Shabbat Shuva').sephard = [r('הושע', '14:2', '14:10'), r('מיכה', '7:18', '7:20')];
}

/// יום ו' דחנוכה הוא תמיד ר"ח, וכל שבת בחנוכה חוץ מיום ח' מפטירה "רני ושמחי".
function mergeChanukah(list) {
  Object.assign(find(list, 'h:Chanukah Day 1 (on Shabbat)'), { id: 'h:Shabbat Chanukah', name: 'שבת חנוכה' });
  Object.assign(find(list, 'h:Chanukah Day 8 (on Shabbat)'), { id: 'h:Shabbat Zot Chanukah', name: 'שבת זאת חנוכה' });
}

/// פנחס חל לכל המוקדם בי"ז בתמוז, ורק אז מפטיר "ויד ה'"; "דברי ירמיהו" נקרא
/// בפנחס או במטות, ו"שמעו" במטות-מסעי או במסעי.
function renameThreeWeeks(list) {
  find(list, 'p:Pinchas').name = 'פנחס - כשחל בי"ז בתמוז';
  find(list, 'p:Matot').name = 'פנחס או מטות';
  find(list, 'p:Masei').name = 'מטות-מסעי או מסעי';
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

/// שבתות ר"ח שאינן בנתוני המקור. שו"ע ורמ"א תכה,א–ב.
function addRoshChodeshVariants(list) {
  const rc = find(list, 'h:Shabbat Rosh Chodesh');
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
}

function markLand(list) {
  for (const h of list) {
    h.land = DIASPORA_ONLY.includes(h.id) ? 'diaspora' : 'both';
  }
}

/// קדושים לאשכנז — יש המסיימים בכב, טז.
// ממתין לבירור: מנהג הגר"א (הפטרות אחרי מות וקדושים מתחלפות באשכנז) אינו מיוצג.
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
