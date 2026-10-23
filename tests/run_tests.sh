#!/bin/sh
# Run the fin-sqlite test suite. Requires finc on PATH and libsqlite3
# on the system (Ubuntu ships libsqlite3.so.0 by default).
# The FIN_CC wrapper adds libsqlite3 to the link; override FIN_CC to use
# a -lsqlite3 wrapper instead when libsqlite3-dev is installed.
set -e
cd "$(dirname "$0")/.."
FIN_CC="${FIN_CC:-./fincc-sqlite}" finc -I src tests/test_sqlite.fin -o test_sqlite
./test_sqlite
