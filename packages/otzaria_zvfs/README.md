# otzaria_zvfs

A read-only SQLite VFS (`zvfs`) that serves a database stored as independently
zstd-compressed pages (`.zdb`), plus a streaming converter from a plain SQLite
file (or a zstd stream of one) to `.zdb`.

The native library does **not** bundle SQLite: it is a loadable-extension style
module that registers against the SQLite already loaded by `package:sqlite3`.
Files without the `.zdb` magic pass through to the default VFS unchanged.

Stage S5a: read path only. Writes to a `.zdb` return `SQLITE_READONLY`.

## Usage

```dart
import 'package:otzaria_zvfs/otzaria_zvfs.dart';
import 'package:sqlite3/sqlite3.dart';

ZVfs.register(cacheBytesPerFile: 16 << 20); // once per process, any isolate
final db = sqlite3.open(path, vfs: ZVfs.name, mode: OpenMode.readOnly);

final result = await convertToZdb(
  source: ZdbSource.zstdFile('seforim.db.zst'), // or .file / .stream
  destination: 'seforim.zdb',
  onProgress: (p) => print(p.fraction),
  cancellationToken: token,
);
isZdb('seforim.zdb');          // magic check only
readZdbInfo('seforim.zdb');    // validates header + dictionary + index
await verifyZdb('seforim.zdb'); // decodes every frame, checks content hash
```

`convertToZdb` runs on a worker isolate; compression uses a bounded pool of
native threads (`threads`, default `cores - 1`, max 16). Memory is bounded by
two batches of `batchBytes` (default 16MB, clamped to 256MB) plus their
compressed output. A zstd source may use a long window (`seforim.db.zst` is
made with `--long=31`): the decoder accepts up to 2^31 (2^30 on 32-bit) and
allocates the window the stream declares, so such a source needs about 2GB
of RAM while converting. The output goes to `<destination>.part` and is
renamed on success; on error or cancellation the partial file is deleted.
A crash leaves the `.part` behind; the next run overwrites it.

Source rules: must start with a valid SQLite header; the length must be a
multiple of the page size and at least the page count in the header
(catches truncated streams). A file source with a non-empty `-wal` is
rejected. A WAL-mode source is served with a rollback-mode header
(bytes 18/19 = 1, compat bit 0), so read-only opens need no `-shm`.

## File format v1.1

All integers little-endian. A file is:

```
[0, 4096)                header (256-byte core + reserved zeros)
[4096, 4096+dictLength)  zstd dictionary (optional)
frames                   frame i = one zstd frame of framePages pages
[indexOffset, EOF)       index: (frameCount + 1) x u64 absolute offsets
```

Header core:

| off | size | field | notes |
|----:|----:|---|---|
| 0 | 8 | magic | `4F 54 5A 5A 44 42 1A 0A` ("OTZZDB\x1a\n") |
| 8 | 2 | formatMajor | 1. Readers refuse other majors (fixed offset forever) |
| 10 | 2 | formatMinor | 1. Additive changes only; readers accept higher minors |
| 12 | 4 | headerSize | 4096 |
| 16 | 4 | incompatFeatures | reader must know every bit set, else refuses; bit 0 = lock gap |
| 20 | 4 | compatFeatures | ignorable; bit 0 = WAL header patched |
| 24 | 4 | pageSize | SQLite page size, power of two 512..65536 |
| 28 | 4 | framePages | pages per frame (converter uses 1); frameBytes <= 16MB |
| 32 | 8 | logicalSize | size SQLite sees; multiple of pageSize |
| 40 | 8 | frameCount | ceil(logicalSize / frameBytes) |
| 48 | 4 | codec | 1 = zstd, magicless frame, content size + checksum, no dictID |
| 52 | 4 | level | informational |
| 56 | 8 | dictOffset | 4096 |
| 64 | 4 | dictLength | 0..1MB; 0 = no dictionary |
| 68 | 4 | dictId | zstd dictionary id (0 when none) |
| 72 | 8 | dictXxh64 | XXH64(dict) |
| 80 | 8 | indexOffset | index start; indexOffset + indexLength == file size |
| 88 | 8 | indexLength | (frameCount + 1) * 8 |
| 96 | 8 | indexXxh64 | XXH64(index bytes) |
| 104 | 8 | contentXxh64 | XXH64 of the logical content |
| 112 | 16 | fileUuid | random per file; overlays bind to it |
| 128 | 8 | createdUnixMs | informational |
| 136 | 32 | dictName | ASCII, NUL-terminated, e.g. `seforim-v1` |
| 168 | 40 | reserved | zero; future minors add fields here |
| 208 | 8 | gapStart | 1.1, with incompat bit 0: padding start (else 0) |
| 216 | 8 | gapEnd | 1.1, with incompat bit 0: padding end (else 0) |
| 224 | 24 | reserved | zero |
| 248 | 8 | headerXxh64 | XXH64 of bytes [0, 248) |

`index[0]` is the first byte after the dictionary, `index[frameCount]` equals
`indexOffset`, offsets strictly increase and no frame exceeds
`ZSTD_compressBound(frameBytes) + 64`. Frame `i` decodes to
`min(frameBytes, logicalSize - i * frameBytes)` bytes. Frame `i` occupies
`[index[i], index[i+1])`, except with a lock gap (below).

### SQLite lock bytes (1.1)

SQLite locks bytes `[0x40000000, 0x40000000 + 512)` of every database file
(PENDING, RESERVED and the SHARED range), and on Windows those locks are
mandatory: while another handle holds them, reading those bytes fails with
`ERROR_LOCK_VIOLATION`, which surfaced as `SQLITE_IOERR` for the page whose
frame covered them. SQLite never uses its own pending-byte page; the converter
likewise never places frame or index bytes there. When the next frame (or the
index) would touch the range, it writes zeros from the current offset up to
`0x40000000 + 512`, records `gapStart`/`gapEnd`, sets incompat bit 0 and goes
on after the gap. The entry `index[j] == gapEnd` then starts the next frame
(or the index), and frame `j-1` ends at `gapStart` (the gap may also follow the
dictionary directly). Readers never read the gap. Files that do not reach the
range (under 1GB) carry no gap and no flag, and are readable by 1.0 readers;
a file with a gap is refused by readers that do not know the bit, instead of
being decoded with padding appended to a frame.

### Validation

On open everything is checked before first use: magic, major, header checksum,
every field range above, file size vs index end, dictionary hash and id, index
hash, index monotonicity and frame bounds. Every frame read checks the zstd
frame header (content size equals the expected length, checksum flag set, no
dictID), decodes into a buffer of exactly that size and verifies the frame
checksum. Failures surface as `SQLITE_CORRUPT` (open or read), an unknown
major or incompat bit as `SQLITE_CANTOPEN`; nothing is read out of bounds.

## Dictionaries and versions

The dictionary is trained at build time and **embedded in every `.zdb`**
(about 112KB against ~2GB), so a reader never needs a dictionary registry and
files made with an old dictionary stay readable forever.

The converter picks a dictionary by name from the built-in registry in
`src/zvfs_dicts.c` (index 0 = newest), or takes custom bytes.

| name | id | bytes | sha256 |
|---|---|---|---|
| `seforim-v1` | 1702679322 | 114688 | `d1f558835b17b2e90c74631e90f0690fbce850b5d1ef0331bb26c8248c65e75e` |

`seforim-v1` was trained on 6000 random 16KB pages (xorshift seed
`0x9E3779B97F4A7C15`) of the 7,910,178,816-byte `seforim.db` of 29/9/2026:

```
zvfs_cli train <seforim.db> src/dicts/seforim_v1.inc 6000 112
```

To add a new dictionary: train into `src/dicts/seforim_v2.inc` (rename the
array), add it at the top of `k_dicts`, add the name/id/sha256 constants in
`lib/src/convert.dart` and a row above. Never modify a shipped `.inc`.

## Overlay attachment (S5b)

The base `.zdb` is immutable. S5b adds writes as an append-only overlay in a
sidecar `<path>-zovl` that binds to the base by `fileUuid` + `contentXxh64`
and maps page numbers to newer frames; reads consult the overlay first.
This needs no change to the base format. Guard in this stage: when
`<path>-zovl` exists, the S5a reader refuses to open the base
(`SQLITE_CANTOPEN`) instead of silently serving stale pages. An overlay kept
inside the same file would need a new `incompatFeatures` bit, which S5a
readers already refuse.

## Runtime model

- Each connection has its own base file handle; locking and shm calls pass
  through to the base VFS (io_methods v3). `xFetch` returns no mapping, so
  mmap is effectively off; `SQLITE_FCNTL_MMAP_SIZE` reports 0.
- Opened read-write, a `.zdb` still reports `SQLITE_OPEN_READONLY`, so the
  pager is read-only.
- Per file (path + header identity) one decoded index and one LRU of decoded
  frames is shared by all connections and isolates. Its byte budget is
  `ZVfs.cacheBytesPerFile` (default 16MB, 0 disables it). The lock is held
  only for the lookup/insert; reading and decompression run outside it, with
  `ZSTD_DCtx` objects from a shared pool.
- A replaced file (different header) gets a fresh state; old connections keep
  the old one until they close.
- `isZdb`, `readZdbInfo` and the C probe/reader never open a file that a
  connection of this process has open through zvfs: on POSIX closing any
  descriptor of a file drops every fcntl lock the process holds on it, which
  would let another process take the write lock under a live reader. They
  answer from the open state instead (`readZdbBytes`/`verifyZdb`:
  `ZdbException.busy`); `ZVfs.isOpen(path)` tells. Files open through another
  VFS in the same process are not tracked: do not probe those.
- A file is recognized by its full path (`xFullPathname`, which resolves
  symlinks on POSIX). A hardlink, or a different letter case on a
  case-insensitive file system (Windows, APFS), is not recognized as the same
  file: open and probe a library through one spelling of its path.

## Tests

```
dart test                                   # Dart: roundtrip, fuzz, isolates...
cmake -S test/c -B build/c -DZVFS_SQLITE_AMALGAMATION=<dir with sqlite3.c>
cmake --build build/c && ctest --test-dir build/c   # C: core + VFS
```

`ZVFS_FUZZ_ITERS` sets the fuzz iteration count for both. The C tests also
run under ASan/UBSan and TSan on Linux (see `.github/workflows/zvfs.yml`).

`tool/bench_live.dart` benchmarks against a real database (outside CI).

## Third-party code

- `third_party/zstd`: zstd 1.5.7, unmodified `lib/` of the official release
  tarball (sha256 `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3`),
  used under its BSD license (`LICENSE`; `COPYING` is the GPLv2 alternative).
- `third_party/sqlite`: `sqlite3.h` and `sqlite3ext.h` from the SQLite 3.53.4
  amalgamation (public domain), matching the SQLite that `package:sqlite3`
  3.6.0 loads.

## Platforms

The native code is C99 with a small platform layer (Win32 or POSIX threads,
`pread`/`pwrite`, 64-bit offsets, `pread64` on 32-bit Android). zstd symbols
are hidden: `ZSTDLIB_VISIBLE` is empty and non-Windows builds use
`-fvisibility=hidden`, so only `zvfs_*` and `sqlite3_otzariazvfs_init` are
exported and zstd cannot clash with `zstandard_native` or tantivy's zstd.

| platform | status |
|---|---|
| Windows x64 | built by the hook, Dart + C tests pass locally |
| Linux x64 | C tests (plus ASan/UBSan/TSan) pass in WSL; Dart tests in CI |
| macOS | CI job; not run locally |
| Android | CI cross-compile of the library (NDK, arm64/armv7/x86_64) |
| iOS | CI cross-compile of the library (Xcode, arm64) |
