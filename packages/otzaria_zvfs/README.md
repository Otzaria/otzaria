# otzaria_zvfs

A SQLite VFS (`zvfs`) that serves a database stored as independently
zstd-compressed pages (`.zdb`), takes writes into an append-only overlay
sidecar (`<path>-zovl`), and a streaming converter from a plain SQLite file
(or a zstd stream of one) to `.zdb`, which also compacts base + overlay.

The native library does **not** bundle SQLite: it is a loadable-extension style
module that registers against the SQLite already loaded by `package:sqlite3`.
Files without the `.zdb` magic pass through to the default VFS unchanged.

Stage S5a: read path. Stage S5b: write path (overlay) and compaction. The
base `.zdb` is never modified; a read-only open still refuses writes.

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

final rw = sqlite3.open(path, vfs: ZVfs.name); // writes go to <path>-zovl
readZdbOverlayInfo(path);       // commits, size, mapped pages
await compactZdb(path);         // no connection may be open (see below)
await installZdb(path, download); // a downloaded .zdb becomes the base
ZVfs.register(makeDefault: true); // VFS-less opens (the updater) use zvfs
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

## File format v1.2

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
| 10 | 2 | formatMinor | 2. Additive changes only; readers accept higher minors |
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
| 168 | 16 | derivedFromUuid | 1.2: base this one was compacted from (else 0) |
| 184 | 16 | includesOverlayUuid | 1.2: the overlay it includes (else 0) |
| 200 | 8 | includesOverlaySeq | 1.2: last commit of that overlay it includes |
| 208 | 8 | gapStart | 1.1, with incompat bit 0: padding start (else 0) |
| 216 | 8 | gapEnd | 1.1, with incompat bit 0: padding end (else 0) |
| 224 | 24 | reserved | zero; future minors add fields here |
| 248 | 8 | headerXxh64 | XXH64 of bytes [0, 248) |

Minor 2 only adds the lineage fields; older readers ignore them and read a
compacted file as an ordinary base. The converter writes minor 2.

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

(`zvfs_cli`: see Command-line tool.)

To add a new dictionary: train into `src/dicts/seforim_v2.inc` (rename the
array), add it at the top of `k_dicts`, add the name/id/sha256 constants in
`lib/src/convert.dart` and a row above. Never modify a shipped `.inc`.

## Overlay `<path>-zovl` (S5b)

The base is immutable; every write lands in an append-only sidecar. S5a
readers refuse to open a base while `<path>-zovl` exists (`SQLITE_CANTOPEN`),
and the sidecar exists from the first write until a compaction replaces the
base, so an old reader never serves stale pages. The overlay has its own
magic and version, so the base format did not need an incompat bit.

### Format 1.0

All integers little-endian; records start 16-byte aligned (zero padding).

Header, 128 bytes:

| off | size | field | notes |
|----:|----:|---|---|
| 0 | 8 | magic | `4F 54 5A 5A 4F 56 4C 0A` ("OTZZOVL\n") |
| 8 | 2 | formatMajor | 1; readers refuse other majors |
| 10 | 2 | formatMinor | 0; additive changes only |
| 12 | 4 | headerSize | 128 |
| 16 | 4 | incompatFeatures | must be known, else refused |
| 20 | 4 | compatFeatures | ignorable |
| 24 | 4 | pageSize | equals the base page size |
| 28 | 4 | recordAlign | 16 |
| 32 | 16 | baseUuid | binding: base `fileUuid` ... |
| 48 | 8 | baseContentXxh64 | ... + `contentXxh64` ... |
| 56 | 8 | baseLogicalSize | ... + `logicalSize` |
| 64 | 16 | overlayUuid | random per sidecar; seeds the checksum chain |
| 80 | 8 | createdUnixMs | informational |
| 88 | 32 | reserved | zero |
| 120 | 8 | headerXxh64 | XXH64 of bytes [0, 120) |

Page record, 32 bytes + payload:

| off | size | field |
|----:|----:|---|
| 0 | 4 | tag `OVPG` (0x4750564F) |
| 4 | 4 | pgno (0-based page index) |
| 8 | 4 | payloadLength (1 .. compressBound(pageSize)+64) |
| 12 | 4 | flags (0) |
| 16 | 8 | XXH64(payload) |
| 24 | 8 | chain = XXH64(bytes [0, 24), seed = previous chain) |
| 32 | n | one magicless zstd frame of exactly pageSize bytes (level 3, base dictionary, content size + checksum, no dictID) |

Commit record, 48 bytes:

| off | size | field |
|----:|----:|---|
| 0 | 4 | tag `OVCM` (0x4D43564F) |
| 4 | 4 | page records since the previous commit |
| 8 | 8 | flags + reserved (0) |
| 16 | 8 | seq (previous + 1, first = 1) |
| 24 | 8 | logicalSize in bytes (file size SQLite sees) |
| 32 | 8 | reserved (0) |
| 40 | 8 | chain = XXH64(bytes [0, 40), seed = previous chain) |

The chain starts at XXH64(header) and runs through every record, so a commit
record vouches for every byte before it: one fsync per commit suffices, as in
SQLite's WAL. A commit may carry no page records (a truncate or growth).

### Recovery (open and refresh)

1. A sidecar of at most 128 bytes is a torn creation (records are appended
   only after the header is synced): the base alone is served, and the next
   writer rewrites it. A longer one must have a valid header bound to this
   base, else `SQLITE_CORRUPT` (unknown major/incompat: `SQLITE_CANTOPEN`).
2. Records are validated in order: tag, bounds, payload hash, chain; a
   commit also needs `seq = last + 1` and the right record count. The page
   records of a batch are applied only at its commit: map entries, then the
   logical size (dropping pages past it). The scan stops at the first invalid
   or incomplete record; everything after the last valid commit is ignored.
3. Readers never truncate. The next writer, holding SQLite's write lock,
   truncates the sidecar to the last commit before its first append; the
   chain also rejects any stale bytes that survive.

Semantics: a commit is durable once `xSync` returns; unsynced commits may be
lost on power loss, which SQLite already tolerates. What survives is always
a prefix of commits, a stronger promise than a plain file's arbitrary subset
of unsynced sectors.

### Write path

- Writes are split into pages (partial pages are read-modify-write),
  compressed and appended; the page map is updated at once, so the process
  sees its own writes like a page cache would.
- Pending records are sealed with a commit record at `xSync` (then fsynced),
  and before any point where another connection could learn of them:
  `xUnlock`, `xShmLock` unlock, `SQLITE_FCNTL_CKPT_DONE` (the checkpoint
  publishes `nBackfill`, possibly without `xSync` when `synchronous=OFF`),
  `xTruncate` and `xClose`. Sealing early is always safe.
- The rollback journal, WAL and shm stay plain files of the base VFS. A
  failed transaction writes the old pages back; they are new records.
- If a commit record cannot be written or an fsync fails, the file state is
  poisoned: every later operation fails with an I/O error until all its
  connections close and it is reopened from disk.
- Page map: 4 bytes per page (record offset / 16) in lazily allocated leaves
  of 4096 pages, so sparse maps stay small on 32-bit too (480K pages: 1.9MB).
  The sidecar is limited to 64GB (then `SQLITE_FULL`; compact).

### Concurrency and processes

All connections of a process share one state per file (base index, decoded
page LRU, page map). SQLite's locks already guarantee that nobody reads a
page while it changes (rollback: EXCLUSIVE; WAL: the checkpoint only
backfills frames readers take from the WAL), so the map needs only a mutex.

Several processes are supported. The writer is whoever holds SQLite's write
lock; every other process picks up new commits when SQLite takes a lock
(`xLock`, and `xShmLock` for WAL readers and checkpointers), by scanning only
the sidecar bytes it has not seen (a resumed scan re-checks its last record,
so a rewritten tail is detected). Sidecar I/O goes through the base VFS (no
locks on the sidecar itself). Requirements: all processes use this VFS, and
the files are on a local filesystem with a coherent page cache.

### Compaction

`compactZdb(path)`:

1. refuses if the file is open in this process (checked before anything
   opens it), or a non-empty `-journal` or `-wal` exists (the logical content
   is then not base + overlay);
2. streams the logical content into `<path>.new` (a new base with the same
   dictionary, lineage = old `fileUuid` + `overlayUuid` + last `seq`) and
   fsyncs it; `verify` decodes it completely;
3. takes `<path>-zlck` exclusively (see below), re-checks that the overlay
   did not move, then renames `.new` over the base durably
   (`MOVEFILE_WRITE_THROUGH`; POSIX: rename + directory fsync);
4. deletes the sidecar and releases the lock.

A crash before 3 leaves the old pair (plus a stale `.new`). Between 3 and 4
the old sidecar no longer binds to the new base, but the base names it
(`includesOverlayUuid`) and its seq is not newer: it is ignored as obsolete
and replaced by the next write. An obsolete sidecar that is still there at
the next compaction is named by that base too, so the same crash window stays
harmless however often it repeats. An obsolete or torn sidecar is scanned once
and then only re-checked by size and header, not rescanned on every lock.

**Swap lock `<path>-zlck`.** Every process that has a `.zdb` open through
zvfs holds a shared lock on byte 0 of `<path>-zlck` (one descriptor per
process and path, opened with the first connection and closed with the last,
so no other close drops it on POSIX). It is taken before the base is opened.
All isolates of a process (in Otzaria: all its windows) share that one
descriptor, so between them the lock proves nothing; the in-process registry
refuses the swap instead.
The swap needs it exclusively: while any connection of any process is open it
fails with `ZdbException.busy`, and an open that meets a swap in progress
waits for it (up to 5s, then `SQLITE_BUSY`). The empty file stays next to the
base; never delete it while the database may be open (a new file would split
the lock). Where it cannot be created or locked (read-only directory or
file system, no lock support, a directory that is not on disk because the
base VFS is not the OS file system: `EACCES`/`EROFS`/`ENOLCK`/`ENOENT`)
connections open
without it, and a swap there fails; other errors fail the open
(`SQLITE_CANTOPEN`). So processes that cannot create `-zlck` (another user
with read access only) are not protected from a swap: give every process
that opens the library write access to its directory. The wait for a swap
runs without any global lock: other files open and close meanwhile.
On a case-insensitive APFS a second spelling of the same path in this process
is not recognized, so the swap's own descriptor could drop that process's
shared lock (theoretical: open the library through one spelling).

### Install

`installZdb(path, candidate)` (C: `zvfs_install`) makes a freshly downloaded
`.zdb` the base of `path`, under the same swap lock as compaction:

1. refuses with `ZdbException.busy` if `path` is open in this process
   (checked before anything opens it) or `-zlck` cannot be taken exclusively
   (another process has it open);
2. validates the candidate: header, dictionary and index, as an open does
   (`notZdb`, `corrupt`, `unsupported`); a candidate that is `path` itself or
   has its own `-zovl` is refused (`invalid`);
3. durably deletes `-journal`, `-wal`, `-shm`, `-zovl` and `.new` of `path`;
4. durably renames the candidate over `path` (`MOVEFILE_WRITE_THROUGH`;
   POSIX: rename + directory fsync). `-zlck` stays.

The deletes come before the rename: a crash in between leaves the old base
without its overlay, an older but consistent database, and the next install
finishes the job. The other order would leave the new base next to an overlay
bound to the old one (`SQLITE_CORRUPT`). Journal and WAL go before the
overlay, because replayed onto the bare old base they would corrupt it; so a
crash between those deletes still serves base + overlay. The candidate must be
on the same volume as `path`. On Windows a delete has no directory flush;
NTFS logs metadata in order, so the write-through rename also makes the
earlier deletes durable.

## Runtime model

- Each connection has its own base file handle; locking and shm calls pass
  through to the base VFS (io_methods v3). `xFetch` returns no mapping, so
  mmap is effectively off; `SQLITE_FCNTL_MMAP_SIZE` reports 0.
- Opened read-only the pager is read-only; opened read-write it writes the
  overlay (see above).
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

## Requirements for the app integration (S5c)

- **Compaction, install and windows.** Otzaria's secondary windows are not
  separate processes: each is its own `FlutterEngine` and isolate in the
  same process (`lib/core/windowing/multi_window_service.dart`,
  `docs/multi-window.md`). `-zlck` therefore does not separate them (a
  process holds one shared lock for all its connections); what does is the
  in-process registry behind `ZVfs.isOpen`, shared by all isolates:
  `compactZdb` and `installZdb` fail with `ZdbException.busy` while any
  connection of any isolate of any window has the library open, and the swap
  lock adds the same for other processes. S5c closes the library in every
  isolate of every window first, retries later on `busy`, and opens it only
  through zvfs: a connection through another VFS or plain `dart:io` is
  neither registered nor holds the swap lock.
- **Converting.** `convertToZdb` reads its source through `dart:io` without
  any check: never convert a database that this process has open through
  another VFS (on POSIX closing that descriptor drops its locks).
- **Replacing the base.** A full download goes in through
  `installZdb(path, candidate)` (see Install), never a plain rename: a
  sidecar bound to the old base makes the new one refuse to open
  (`SQLITE_CORRUPT`).
- **Hot journal after an updater crash.** A read-only open then fails with
  `SQLITE_READONLY_ROLLBACK` until one read-write open rolls the journal back;
  do that once before read-only connections. `immutable=1` must not be used:
  it skips the journal and the overlay refresh.
- **Not on the UI isolate at startup.** Opening a `.zdb` (and `readZdbInfo`)
  replays the overlay synchronously, one sequential read of the sidecar.
- **Leftovers.** A crashed compaction leaves `<path>.new`; delete it (the next
  `compactZdb` overwrites it anyway).
- `isZdb`, `readZdbInfo` and `readZdbOverlayInfo` answer from the open state
  when the path is open through zvfs; `readZdbBytes`, `verifyZdb` and
  `compactZdb` then fail with `ZdbException.busy`. Paths open through another
  VFS in the same process are not tracked: do not probe those.

## Command-line tool

`tool/zvfs_cli.c` is the production CLI (built without the test hooks), for
the pipeline that publishes the library:

```
sh tool/build_cli.sh [out=build/zvfs_cli]    # plain cc/gcc, no cmake; CC, CFLAGS
cmake -S test/c -B build/c -DZVFS_BUILD_CLI=ON -DZVFS_BUILD_TESTS=OFF   # or cmake

zvfs_cli convert <in.db|-> <out.zdb> [--dict NAME | --no-dict] [--level N]
         [--threads N] [--zstd] [--uuid-from-content] [--created-ms MS]
zvfs_cli verify <file.zdb>          # every frame + content hash, then the overlay
zvfs_cli info [--json] <file.zdb>   # every header field, plus the overlay
zvfs_cli export <file.zdb> <out.db> # back to a plain SQLite file
zvfs_cli dicts                      # built-in dictionaries (first = default)
zvfs_cli train <db> <out.inc> [samples] [dict_kb] [seed]
```

`convert` reads a file or stdin (`-`; `--zstd` for a zstd stream), writes
`<out>.part` and renames it on success. Defaults: the newest dictionary,
level 9, 4 threads. The output bytes do not depend on the thread count, but
`fileUuid` is random and `createdUnixMs` is the clock: `--uuid-from-content`
derives the uuid from the XXH64 of every other header field (content hash,
sizes, dictionary, level, index hash; `createdUnixMs` excluded) and
`--created-ms` fixes the timestamp, so the same input, options, CLI build and
zstd version give the same file byte for byte. Two such files with equal
content share a uuid; an overlay made on one is valid on the other.

`info --json` prints the header as read (`logicalSize` is the base image),
64-bit hashes as 16 hex digits and uuids as 32. `export` refuses a base with
a `-zovl` (compact it first) or a pending `-journal`/`-wal`; a WAL-mode source
comes back with the rollback header the zdb serves (bytes 18/19 = 1).
Exit status: 0 ok, 1 failure, 2 usage. CI builds it with `build_cli.sh` on
Linux x64 and arm64 and checks convert, verify, info, export (`cmp` equal to
the source) and reproducibility (`tool/cli_roundtrip.sh`).

## Tests

```
dart test                                   # Dart: roundtrip, fuzz, isolates...
cmake -S test/c -B build/c -DZVFS_SQLITE_AMALGAMATION=<dir with sqlite3.c>
cmake --build build/c && ctest --test-dir build/c   # C: core + VFS
```

C test binaries: `core` (format), `vfs` (read path), `write` (overlay codec,
torn/flipped bytes at every offset, fuzz, SQL equivalence with plain SQLite
byte for byte, compaction windows, install crash points, WAL reader threads), `crash` (patch-shaped
transactions over an in-memory VFS that fails the N-th write or sync and then
drops, reorders or tears unsynced writes), `kill` (child processes killed with
`TerminateProcess`/`SIGKILL`, with a concurrent reader process).

`ZVFS_FUZZ_ITERS` sets the fuzz iteration count for both. `ZVFS_CRASH_STRIDE`
samples fault points (1 = every one), `ZVFS_KILL_ITERS` the kill count. The C
tests also run under ASan/UBSan and TSan on Linux (see
`.github/workflows/zvfs.yml`).

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
| Windows ARM64 | CI job (`windows-11-arm`): build + C tests; not run locally |
| Linux x64 | C tests (plus ASan/UBSan/TSan) pass in WSL; Dart tests in CI |
| Linux arm64 | CI: CLI build (`build_cli.sh`) + roundtrip |
| macOS | CI job; not run locally |
| Android | CI cross-compile of the library (NDK, arm64/armv7/x86_64) |
| iOS | CI cross-compile of the library (Xcode, arm64) |
