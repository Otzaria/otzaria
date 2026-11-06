import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { gunzipSync } from 'node:zlib';

const [validatorArgument, manifestArgument] = process.argv.slice(2);
assert.ok(validatorArgument && manifestArgument,
  'נדרשים נתיב validation.js המקורי ונתיב compat-payloads.json');
const validatorFile = resolve(validatorArgument);
const validatorDirectory = dirname(validatorFile);
assert.equal(validatorFile, resolve(validatorDirectory, 'validation.js'));

// Pin the real validation dependency graph to Website/master dc76f652.
// A replacement validator must never turn this compatibility gate green.
const sourceBlobs = {
  'validation.js': '43d693b57ae40cd3ce3d3e1258f8d0db35c50aaf',
  '../validation-utils.js': 'aa93de62e15882c2845b063ef8452808aab04f2e',
  'products.js': '1019c3c473113ebd7da634357434e83ea242c3d6',
};
for (const [relative, expected] of Object.entries(sourceBlobs)) {
  const source = await readFile(resolve(validatorDirectory, relative));
  const actual = createHash('sha1')
    .update(Buffer.from(`blob ${source.length}\0`)).update(source).digest('hex');
  assert.equal(actual, expected, `מקור המאמת השתנה: ${relative}`);
}
const { validateAppReport, MAX_BODY_BYTES, MAX_MINIDUMP_BYTES } =
  await import(pathToFileURL(validatorFile).href);
const manifest = JSON.parse(await readFile(resolve(manifestArgument), 'utf8'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const textBytes = value => Buffer.from(JSON.stringify(value), 'utf8');
let accepted = 0;
let rejected = 0;

async function check(name, payload, expectedSchema, digests) {
  assert.equal(payload.schema, expectedSchema, `${name}: חוזה שגוי`);
  const result = await validateAppReport(payload);
  if (expectedSchema === 2) {
    assert.equal(result.ok, false, `${name}: השרת הישן קיבל schema 2`);
    assert.equal(result.status, 422, name);
    assert.equal(result.field, 'schema', name);
    rejected += 1;
  } else {
    assert.ok(textBytes(payload).length <= MAX_BODY_BYTES, `${name}: גוף גדול מדי`);
    assert.equal(result.ok, true, `${name}: ${JSON.stringify(result)}`);
    const source = payload.attachments ?? {};
    assert.deepEqual(result.value.diagnostics, source.diagnostics ?? null, `${name}: אבחון`);
    assert.equal(result.value.errorLog, source.errorLog ?? '', `${name}: לוג`);
    assert.deepEqual(
      result.value.images.map(image => image.buffer),
      (source.images ?? []).map(image => Buffer.from(image.data, 'base64')),
      `${name}: בתים של תמונות`,
    );
    if (source.minidump) {
      let raw = Buffer.from(source.minidump.data, 'base64');
      if (raw[0] === 0x1f && raw[1] === 0x8b) {
        raw = gunzipSync(raw, { maxOutputLength: MAX_MINIDUMP_BYTES });
      }
      assert.deepEqual(result.value.minidump.buffer, raw, `${name}: minidump`);
    } else {
      assert.equal(result.value.minidump, null, name);
    }
    accepted += 1;
  }
  if (digests) {
    const source = payload.attachments ?? {};
    if (digests.diagnostics) {
      assert.equal(digest(textBytes(source.diagnostics)), digests.diagnostics, `${name}: אבחון המקור`);
    }
    if (digests.errorLog) {
      assert.equal(digest(Buffer.from(source.errorLog, 'utf8')), digests.errorLog, `${name}: לוג המקור`);
    }
    assert.deepEqual((source.images ?? []).map(image =>
      digest(Buffer.from(image.data, 'base64'))), digests.images, `${name}: תמונות המקור`);
    if (digests.minidump) {
      const raw = gunzipSync(Buffer.from(source.minidump.data, 'base64'),
        { maxOutputLength: MAX_MINIDUMP_BYTES });
      assert.equal(digest(raw), digests.minidump, `${name}: קובץ הקריסה המקורי`);
    }
  }
  console.log(`${name}: schema ${expectedSchema}, ${result.ok ? 'נקלט ללא אובדן' : 'נדחה במפורש בשדה schema'}`);
}

const appBodies = Object.entries(manifest.bodies).filter(([id]) => id.startsWith('app-'));
assert.equal(appBodies.length, 2, 'נדרשים דיווח רגיל חדש ודיווח קיים');
for (const [name, payload] of appBodies) await check(name, payload, 1);
assert.ok(manifest.directBodies['with-dump'].attachments.minidump,
  'שליחה ישירה חייבת לכלול קובץ קריסה');
const protectedDump = manifest.extendedPayloads[manifest.protectedDumpReportId];
assert.equal(protectedDump.schema, 2, 'קובץ קריסה חדש חייב להישמר במסלול המוגן');
assert.deepEqual(protectedDump.minidump,
  manifest.directBodies['with-dump'].attachments.minidump,
  'בחירת חוזה HTTP אינה משנה את קובץ הקריסה השמור');
assert.ok(manifest.directBodies['exact-diagnostics-log']);
for (const [name, payload] of Object.entries(manifest.directBodies)) {
  await check(`direct-${name}`, payload, 1);
}

const expectedCases = {
  ordinary_text_image_dump: 1,
  legacy_diagnostics_exact_300000: 1,
  legacy_diagnostics_plus_one: 2,
  legacy_log_exact_250000_utf8: 1,
  legacy_log_plus_one: 2,
  legacy_text_envelope_exact_700000: 1,
  legacy_text_envelope_plus_one: 2,
  legacy_image_exact_5_mib: 1,
  legacy_image_plus_one: 2,
};
assert.deepEqual(manifest.transportCases.map(item => item.name).sort(),
  Object.keys(expectedCases).sort(), 'חסרים מקרי גבול אמיתיים מהלקוח');
for (const fixture of manifest.transportCases) {
  const { name, payload } = fixture;
  assert.ok(fixture.digests && Array.isArray(fixture.digests.images), name);
  for (const field of ['diagnostics', 'errorLog', 'minidump']) {
    if (payload.attachments?.[field] != null) {
      assert.match(fixture.digests[field], /^[a-f0-9]{64}$/, `${name}: ${field}`);
    }
  }
  if (name.startsWith('legacy_diagnostics_')) {
    assert.equal(textBytes(payload.attachments.diagnostics).length,
      name.endsWith('plus_one') ? 300001 : 300000, name);
  } else if (name.startsWith('legacy_log_')) {
    assert.equal(Buffer.byteLength(payload.attachments.errorLog, 'utf8'),
      name.endsWith('plus_one') ? 250001 : 250000, name);
  } else if (name.startsWith('legacy_text_envelope_')) {
    assert.equal(textBytes(payload).length,
      name.endsWith('plus_one') ? 700001 : 700000, name);
  } else if (name.startsWith('legacy_image_')) {
    assert.equal(Buffer.from(payload.attachments.images[0].data, 'base64').length,
      5 * 1024 * 1024 + (name.endsWith('plus_one') ? 1 : 0), name);
  }
  await check(name, payload, expectedCases[name], fixture.digests);
}

const control = await validateAppReport({ ...appBodies[0][1], schema: 2 });
assert.equal(control.ok, false, 'בקרת הרגרסיה חייבת להידחות בשרת הישן');
assert.equal(control.field, 'schema');
console.log(`עבר: ${accepted} מטענים נקלטו ללא אובדן, ${rejected} מטעני schema 2 נדחו ללא הורדה מאבדת מידע.`);
