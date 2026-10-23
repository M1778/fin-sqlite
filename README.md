# fin-sqlite

A SQLite binding for Fin: a thin, honest wrapper over the system
libsqlite3 C API. No SQL is re-implemented here — parsing, storage,
transactions, and indexing are all real SQLite, proven by opening a
Fin-written database file with the independent `sqlite3` CLI.

> **Verification status:** VERIFIED against finc 0.4.0 (contract 3):
> 99 assertions pass with exit 0, both examples run, and the
> file-backed example is cross-checked with the `sqlite3` CLI.

## Install

Requires the `finn` package manager (https://github.com/M1778/finn):

```sh
finn add M1778/fin-sqlite
```

Runtime requirement: libsqlite3 (ships with Ubuntu by default; on other
systems install the SQLite runtime package).

## Building

Linking needs libsqlite3 added to finc's link step. This repo ships a
`FIN_CC` wrapper for that (the same pattern other Fin libraries use for
extra C libraries):

```sh
FIN_CC=./fincc-sqlite finc -I src tests/test_sqlite.fin -o test_sqlite
./test_sqlite
```

If you have libsqlite3-dev installed, a wrapper doing
`exec cc "$@" -lsqlite3` works the same way. The wrapper must be a
single executable path — finc passes it no flags of its own.

## Quick example

```fin
import { Db, SqlTable, sqlite_open, sqlite_close, sqlite_exec,
         sqlite_query_all, sqlite_table_rows, sqlite_table_get,
         sqlite_free_table } from sqlite::fin;

fun main() <noret> {
    let db <Db> = sqlite_open(":memory:");
    sqlite_exec(&db, "CREATE TABLE t(name TEXT); INSERT INTO t VALUES('ada');");
    let t <SqlTable> = sqlite_query_all(&db, "SELECT name FROM t");
    printf("%s\n", sqlite_table_get(&t, 0, 0));   // ada
    sqlite_free_table(&t);
    sqlite_close(&db);
}
```

> Import spelling: `sqlite::fin` means module `sqlite` (the file
> `src/sqlite.fin`), namespace `fin`. Import the names you need
> **by name** — qualified calls (`fin.sqlite_open(...)`) are refused by
> the backend; see `docs/guide/10-modules-and-imports.md` in the Fin repo.

## API reference

### Opening and closing

| Function | Notes |
|---|---|
| `sqlite_open(path) <Db>` | `":memory:"` for a temporary database. `ok` is false on failure — but the handle is still valid (it carries the error): read `sqlite_errmsg`, then still call `sqlite_close`. |
| `sqlite_close(db) <int>` | Result code, 0 on success. Do not use the `Db` afterwards. |
| `sqlite_errmsg(db) <string>` | FRESH heap string (free it with `free_str`). `""` for a null handle. |
| `sqlite_exec(db, sql) <int>` | Statements that return no rows (`CREATE`, `INSERT`, `UPDATE`, `DELETE`, `BEGIN`, `COMMIT`, `ROLLBACK`, ...). Multiple statements in one string are fine. 0 on success. |
| `sqlite_last_rowid(db) <long>` | Row id of the most recent successful `INSERT`. |
| `sqlite_changes(db) <int>` | Rows modified by the most recent `INSERT`, `UPDATE`, or `DELETE`. |

### Prepared statements

| Function | Notes |
|---|---|
| `sqlite_prepare(db, sql) <Stmt>` | Prepares the first statement in the string. `ok` is false on failure; read the database's `sqlite_errmsg`. |
| `sqlite_step(stmt) <int>` | `100` = one more row, `101` = done, anything else = error. A statement with a null handle answers `-1` instead of touching SQLite. |
| `sqlite_reset(stmt) <int>` | Rewind for another pass; bindings are kept. |
| `sqlite_finalize(stmt) <int>` | Destroys the statement and frees every bound-text clone. Do not use the `Stmt` afterwards. Safe on a failed `Stmt` (returns 0). |

### Binding parameters (1-based `?` placeholders)

`sqlite_bind_int`, `sqlite_bind_int64`, `sqlite_bind_double`,
`sqlite_bind_null` — each returns the SQLite result code (0 on success),
or `-1` for a null statement handle.

`sqlite_bind_text(stmt, idx, value)` clones the value into the
statement, so the caller's string may be freed right after binding.
The clones are freed by `sqlite_finalize` — a statement that is never
finalized leaks them. (Why clone: the binding uses `SQLITE_STATIC`,
a null destructor, because Fin cannot express SQLite's `SQLITE_TRANSIENT`
function-pointer destructor.)

### Reading columns (0-based)

| Function | Notes |
|---|---|
| `sqlite_col_count(stmt) <int>` | Columns in the result row. |
| `sqlite_col_type(stmt, col) <int>` | `1` INTEGER, `2` REAL, `3` TEXT, `4` BLOB, `5` NULL. |
| `sqlite_col_is_null(stmt, col) <bool>` | True exactly when the type is 5. |
| `sqlite_col_int` / `sqlite_col_int64` / `sqlite_col_double` | Typed reads. |
| `sqlite_col_text(stmt, col) <string>` | FRESH heap string (free it). NULL answers `""`; a BLOB is truncated at its first NUL byte (see Limitations). |
| `sqlite_col_bytes(stmt, col) <int>` | Byte length of a TEXT or BLOB value. |
| `sqlite_col_name(stmt, col) <string>` | FRESH heap string (free it). |

### Whole-query helper

`sqlite_query_all(db, sql) <SqlTable>` runs a query and collects every
row as text: INTEGER via `%d`, REAL via `%g`, TEXT verbatim, NULL and
BLOB as `""`. `SqlTable.ok` is false when preparation failed or a step
errored (already-collected rows are still in the table — check `ok`
before trusting it).

`sqlite_table_rows(t)`, `sqlite_table_get(t, row, col)` (BORROWED —
never free it, `""` out of range), `sqlite_free_table(t)` (frees every
cell, every column name, and all three collections).

## Ownership summary

- Fresh (caller frees with `free_str`): `sqlite_errmsg`,
  `sqlite_col_text`, `sqlite_col_name`, and every `SqlTable` cell you
  obtain through `sqlite_query_all`'s internals — but NOT through
  `sqlite_table_get`, which borrows.
- Borrowed (never free): `sqlite_table_get` results.
- Owned by the statement until finalize: `sqlite_bind_text` clones.

## Limitations (v0.1.0, honest list)

- **BLOB values have no reader yet.** `sqlite_col_type` reports them
  (4) and `sqlite_col_bytes` gives their length, but `sqlite_col_text`
  truncates at the first NUL byte. A `sqlite_col_blob` returning a
  byte array is the next feature (it needs a Fin-side byte-buffer
  convention first).
- **NULL renders as `""` in `SqlTable`.** Exact NULL handling needs
  the prepared-statement API (`sqlite_col_is_null`).
- **Integers past int32 range lose precision in `SqlTable`** (`%d`
  rendering). The exact path is `sqlite_col_int64`.
- **One statement per prepare.** `sqlite_prepare` prepares only the
  first statement in the string (SQLite's rule); use `sqlite_exec`
  for multi-statement scripts.
- **No `sqlite3_open_v2` flags** (read-only mode, URI filenames,
  full-mutex control). Plain `sqlite_open` covers the common cases.
- **No extension loading, no custom SQL functions, no authorizer.**
  All are possible later through the same `@define` pattern.
- **Linking needs the `FIN_CC` wrapper** (see Building). There is no
  way yet for a Fin library to declare a system link dependency in
  `finn.toml`.
- Result codes are literals at use sites (0 / 100 / 101), not named
  constants: `const` declarations do not lower through imports in
  finc 0.4.0, so the library documents the codes instead of faking
  constants that would break importers.

## Design notes

- The binding was proven incrementally, not assumed: a first probe
  showed Fin's `&&void` type expresses SQLite's `sqlite3**`
  out-parameters, and a second probe ran the full
  prepare → bind → step → column cycle before the library was written.
  Both probes live in the agent sandbox, not in this repo.
- Transactions are plain SQL through `sqlite_exec`
  (`BEGIN; ... COMMIT;` / `ROLLBACK;`) — tested, see the test suite.
- Error handling never blames on caller data: bad SQL gives `ok=false`
  / non-zero codes plus a readable `sqlite_errmsg`, never an abort.
