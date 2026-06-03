#!/usr/bin/env bash
# Set the 2 selected platforms in config/platforms.json from two args.
# Used by the on-demand (workflow_dispatch) deploy to apply the chosen pair.
# Validates both keys exist in the catalog and are distinct.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
a="${1:?platform A required}"
b="${2:?platform B required}"

python3 - "$a" "$b" "$REPO_ROOT/config/platforms.json" <<'PY'
import json, sys
a, b, path = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path))
cat = d["catalog"]
bad = [x for x in (a, b) if x not in cat]
if bad:
    sys.exit(f"unknown platform(s) {bad}; valid: {list(cat)}")
if a == b:
    sys.exit("pick two DIFFERENT platforms")
d["selected"] = [a, b]
json.dump(d, open(path, "w"), indent=2)
print(f"selected platforms set to: {[a, b]}")
PY
