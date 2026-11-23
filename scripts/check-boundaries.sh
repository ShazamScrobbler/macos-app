#!/usr/bin/env bash
# Enforces the trust boundaries documented in SECURITY.md (spec §13).
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

# 1. Only ShazamLibrary may reference Shazam's container.
#    TestSupport (test-only fixtures, never linked into the app) builds a fake Shazam folder.
if grep -rnE '4GWDBCF5A4|Group Containers|com\.shazam\.mac' --include='*.swift' Kit/Sources App/Sources \
    | grep -v -e '^Kit/Sources/ShazamLibrary/' -e '^Kit/Sources/TestSupport/'; then
  echo "error: only Kit/Sources/ShazamLibrary may reference Shazam's container" >&2
  fail=1
fi

# 2. ShazamLibrary must not contain networking code.
if grep -rnE 'URLSession|URLRequest|import Network|NWConnection|CFNetwork|NSURLConnection|socket\(|ScrobbleClients' \
    Kit/Sources/ShazamLibrary; then
  echo "error: Kit/Sources/ShazamLibrary must not use networking" >&2
  fail=1
fi

# 3. ShazamLibrary never writes.
if grep -rnE 'readWriteCreate|SQLITE_OPEN_READWRITE|forWritingTo|createFile|removeItem|O_RDWR|O_WRONLY' \
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
