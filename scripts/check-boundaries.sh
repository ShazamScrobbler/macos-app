#!/usr/bin/env bash
# Enforces the trust boundaries documented in SECURITY.md (spec §13).
# BOUNDARY_ROOT overrides the repo root (used to test the check itself).
set -euo pipefail
cd "${BOUNDARY_ROOT:-$(dirname "$0")/..}"
fail=0

# The scanned directories must exist, otherwise every rule would pass vacuously.
for dir in Kit/Sources Kit/Sources/ShazamLibrary App/Sources; do
  if [ ! -d "$dir" ]; then
    echo "error: expected directory $dir is missing" >&2
    exit 1
  fi
done

# found PATTERN DIR... : prints matches; returns 0 if any, 1 if none, aborts on grep errors (exit >= 2).
found() {
  local rc=0
  grep -rnE "$@" || rc=$?
  if [ "$rc" -ge 2 ]; then
    echo "error: grep failed (exit $rc)" >&2
    exit 2
  fi
  [ "$rc" -eq 0 ]
}

# outside PATTERN ALLOWED_ERE DIR... : prints matches whose "file:line:" prefix is not allowed; returns 0 if any.
# Grep errors abort (see `found`).
outside() {
  local pattern=$1 allowed=$2 rc=0 all hits
  shift 2
  all=$(found "$pattern" "$@") || rc=$?
  [ "$rc" -le 1 ] || exit 1
  hits=$(printf '%s\n' "$all" | grep -Ev "$allowed|^$" || true)
  [ -n "$hits" ] || return 1
  printf '%s\n' "$hits"
}

# 1. Only ShazamLibrary may reference Shazam's container.
#    TestSupport (test-only fixtures, never linked into the app) builds a fake Shazam folder.
rc=0
hits=$(found '4GWDBCF5A4|Group Containers|com\.shazam\.mac' --include='*.swift' Kit/Sources App/Sources) || rc=$?
if [ "$rc" -ge 2 ]; then
  echo "error: rule 1 scan failed (exit $rc)" >&2
  exit 1
fi
hits=$(printf '%s\n' "$hits" | grep -v -e '^Kit/Sources/ShazamLibrary/' -e '^Kit/Sources/TestSupport/' -e '^$' || true)
if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  echo "error: only Kit/Sources/ShazamLibrary may reference Shazam's container" >&2
  fail=1
fi

# 2. ShazamLibrary must not contain networking or process-spawning code.
if found 'URLSession|URLRequest|import Network|NWConnection|CFNetwork|NSURLConnection|socket\(|ScrobbleClients|Process\(|NSTask|getaddrinfo|CFStream|CFSocket|URL\(string:|contentsOf:|posix_spawn|system\(|dlopen|NSWorkspace' \
    Kit/Sources/ShazamLibrary; then
  echo "error: Kit/Sources/ShazamLibrary must not use networking" >&2
  fail=1
fi

# 3. ShazamLibrary never writes.
if found 'readWriteCreate|SQLITE_OPEN_READWRITE|forWritingTo|createFile|removeItem|O_RDWR|O_WRONLY|write\(to|write\(toFile|moveItem|copyItem|createDirectory|forUpdating|SQLITE_OPEN_CREATE|forWritingAtPath|O_CREAT|O_APPEND|unlink\(|rename\(|truncate\(|VACUUM|ATTACH' \
    Kit/Sources/ShazamLibrary; then
  echo "error: Kit/Sources/ShazamLibrary must not write files" >&2
  fail=1
fi

# 4. ShazamLibrary's dependencies stay exactly these.
deps=$(swift package --package-path Kit dump-package | python3 -I -c '
import json, sys
target = next(t for t in json.load(sys.stdin)["targets"] if t["name"] == "ShazamLibrary")
print(" ".join(sorted(d["byName"][0] for d in target["dependencies"])))')
if [ "$deps" != "SQLiteLite ScrobbleCore" ]; then
  echo "error: ShazamLibrary dependencies changed: $deps" >&2
  fail=1
fi

# 5. ShazamLibrary's transitive dependencies must not import networking either.
if found 'URLSession|URLRequest|import Network|NWConnection|CFNetwork' Kit/Sources/ScrobbleCore Kit/Sources/SQLiteLite; then
  echo "error: ScrobbleCore and SQLiteLite must not use networking (ShazamLibrary depends on them)" >&2
  fail=1
fi

# 6. Only SQLiteLite opens SQLite; only ShazamLibrary and StateStore construct databases.
#    (TestSupport builds fixture databases, but is never linked into the app.)
if outside 'sqlite3_open' '^Kit/Sources/SQLiteLite/' Kit/Sources App/Sources; then
  echo "error: sqlite3_open may only appear in Kit/Sources/SQLiteLite" >&2
  fail=1
fi
if outside 'SQLiteDatabase\(path:' '^(Kit/Sources/ShazamLibrary/|Kit/Sources/ScrobbleCore/StateStore\.swift:|Kit/Sources/TestSupport/)' Kit/Sources App/Sources; then
  echo "error: SQLiteDatabase(path:) may only appear in ShazamLibrary and ScrobbleCore/StateStore.swift" >&2
  fail=1
fi

exit "$fail"
