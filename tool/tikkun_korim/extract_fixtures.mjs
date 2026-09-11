// חילוץ טקסטי fixture מ-seforim.db (קריאה בלבד) לתיקיית הבדיקות, כ-gzip.
// הטקסט מוחזר בדיוק כמו getBookTextFromDb: content של השורות לפי lineIndex,
// מאוחות ב-"\n".
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const DB = process.env.OTZARIA_SEFORIM_DB ?? path.join(process.env.APPDATA ?? '', 'otzaria/books/seforim.db');
const OUT = path.resolve(process.argv[2] ?? 'test/tools/tikkun_korim/fixtures');

const BOOKS = {
  bereshit: 1,
  shemot: 2,
  vayikra: 3,
  bamidbar: 4,
  devarim: 5,
  shoftim: 7,
  shmuel_b: 9,
  yeshayahu: 12,
  esther: 34,
};

fs.mkdirSync(OUT, { recursive: true });

for (const [id, bookId] of Object.entries(BOOKS)) {
  const sqlFile = path.join(OUT, '.q.sql');
  fs.writeFileSync(
    sqlFile,
    `.mode list\n.separator "\\n"\n.headers off\nSELECT content FROM line WHERE bookId = ${bookId} ORDER BY lineIndex;\n`,
  );
  const raw = execFileSync(
    'sqlite3',
    ['-readonly', DB, '-init', sqlFile, '.quit'],
    { encoding: 'buffer', maxBuffer: 1 << 30 },
  );
  fs.rmSync(sqlFile);
  // sqlite3 מסיים כל שורה ב-"\n"; getLineContents מאחה ב-"\n" בלי סיומת.
  let text = raw.toString('utf8');
  if (text.endsWith('\n')) text = text.slice(0, -1);
  const gz = zlib.gzipSync(Buffer.from(text, 'utf8'), { level: 9 });
  fs.writeFileSync(path.join(OUT, `${id}.txt.gz`), gz);
  console.log(`${id}: chars=${text.length} lines=${text.split('\n').length} gz=${gz.length}`);
}
