# Changelog

## 0.1.0 — 2026-10-23

First build (day 1 of the 2026-10-22 weekly selection). A real SQLite
binding, not a re-implementation: thin `@define` externs over the system
libsqlite3 C API.

- `Db` lifecycle: `sqlite_open` / `sqlite_close` / `sqlite_errmsg`
  (fresh heap string), `sqlite_exec` (multi-statement), `sqlite_last_rowid`,
  `sqlite_changes`.
- Prepared statements: `sqlite_prepare` / `sqlite_step` (100 ROW, 101 DONE)
  / `sqlite_reset` / `sqlite_finalize`, with null-handle guards so a
  failed statement never touches SQLite.
- Bindings (1-based): int, int64, double, text (cloned into the statement
  under SQLITE_STATIC, so callers may free right after binding), null.
- Column reads (0-based): count, type (1/2/3/4/5), is-null, int, int64,
  double, text (fresh heap; NULL renders ""), byte length, name (fresh heap).
- Whole-query helper `sqlite_query_all` → `SqlTable` (flat cells +
  per-row lengths + column names, fincsv-style), with `sqlite_table_rows`
  / `sqlite_table_get` (borrowed) / `sqlite_free_table`.
- Tests: 99 assertions across 7 groups (open/exec, query-all, prepared
  statements, bind types incl. int64 past int32 range and the
  bind-then-free-clone proof, error paths, file persistence across
  reopen, transactions incl. rollback) — all pass, exit 0, stable on
  rerun. Examples: in-memory basic + file-backed todo, the latter
  cross-checked with the independent `sqlite3` CLI (schema + both rows).
- Known limits (see README): no BLOB reader yet, NULL renders "" in
  SqlTable, int64 precision loss in SqlTable, one statement per prepare,
  no open-v2 flags, FIN_CC wrapper required for linking.
