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
    exit 1
  fi
  [ "$rc" -eq 0 ]
}

# 1. Only ShazamLibrary may reference Shazam's container.
#    TestSupport (test-only fixtures, never linked into the app) builds a fake Shazam folder.
hits=$(found '4GWDBCF5A4|Group Containers|com\.shazam\.mac' --include='*.swift' Kit/Sources App/Sources || true)
hits=$(printf '%s\n' "$hits" | grep -v -e '^Kit/Sources/ShazamLibrary/' -e '^Kit/Sources/TestSupport/' -e '^$' || true)
if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  echo "error: only Kit/Sources/ShazamLibrary may reference Shazam's container" >&2
  fail=1
fi

# 2. ShazamLibrary must not contain networking or process-spawning code.
if found 'URLSession|URLRequest|import Network|NWConnection|CFNetwork|NSURLConnection|socket\(|ScrobbleClients|Process\(|NSTask|getaddrinfo|CFStream|CFSocket' \
    Kit/Sources/ShazamLibrary; then
  echo "error: Kit/Sources/ShazamLibrary must not use networking" >&2
  fail=1
fi

# 3. ShazamLibrary never writes.
if found 'readWriteCreate|SQLITE_OPEN_READWRITE|forWritingTo|createFile|removeItem|O_RDWR|O_WRONLY|write\(to|write\(toFile|moveItem|copyItem|createDirectory|forUpdating|SQLITE_OPEN_CREATE' \
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

exit "$fail"
