#!/usr/bin/env bash
# Static validation / lint for the repo. Runs all checks, aggregates failures.
# Used by `make lint` and the GitHub Actions CI workflow.
#   terraform fmt + validate · config sanity · yamllint · shellcheck · kustomize build
#
# Locally, a missing optional tool is a warning; set STRICT=1 (CI does) to make
# missing tools a failure.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
STRICT="${STRICT:-0}"
fail=0

red() { printf '\033[31m%s\033[0m\n' "$1"; }
grn() { printf '\033[32m%s\033[0m\n' "$1"; }
yel() { printf '\033[33m%s\033[0m\n' "$1"; }
sec() { printf '\n=== %s ===\n' "$1"; }
missing() { if [ "$STRICT" = "1" ]; then red "MISSING required tool: $1"; fail=1; else yel "skip: $1 not installed"; fi; }

sec "terraform fmt + validate"
if command -v terraform >/dev/null 2>&1; then
  terraform -chdir=terraform fmt -check -recursive && grn "fmt ok" || { red "terraform fmt: run 'terraform fmt'"; fail=1; }
  for d in terraform terraform/bootstrap; do
    terraform -chdir="$d" init -backend=false -input=false >/dev/null 2>&1 \
      && terraform -chdir="$d" validate >/dev/null && grn "validate ok: $d" || { red "terraform validate failed: $d"; fail=1; }
  done
else missing terraform; fi

sec "config/platforms.json sanity"
python3 - <<'PY' || fail=1
import json, sys
cfg = json.load(open("config/platforms.json"))
cat, sel = cfg.get("catalog", {}), cfg.get("selected", [])
errs = []
if not isinstance(sel, list) or len(sel) != 2:
    errs.append(f"'selected' must have exactly 2 entries, got {sel!r}")
if len(set(sel)) != len(sel):
    errs.append("'selected' entries must be distinct")
bad = [k for k in sel if k not in cat]
if bad:
    errs.append(f"unknown platform key(s) not in catalog: {bad}")
if errs:
    print("\n".join("  - " + e for e in errs)); sys.exit(1)
print(f"  ok: selected={sel} (catalog={list(cat)})")
PY

sec "yamllint (our manifests; vendored k8s/base excluded)"
if command -v yamllint >/dev/null 2>&1; then
  yamllint -c .yamllint.yml \
    k8s/monitoring k8s/overlays/boutique.kustomization.tmpl.yaml \
    cloudbuild .github 2>/dev/null && grn "yamllint ok" || { red "yamllint issues"; fail=1; }
else missing yamllint; fi

sec "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  # Lint our scripts (lib.sh is sourced; source directives handle it).
  shellcheck --severity=warning scripts/*.sh && grn "shellcheck ok" || { red "shellcheck issues"; fail=1; }
else missing shellcheck; fi

sec "kustomize build (rendered overlay + base)"
if command -v kubectl >/dev/null 2>&1; then
  ok=1
  d="$(mktemp -d "k8s/overlays/.render.XXXXXX")"
  sed -e 's/__NS__/boutique-n2/g' -e 's/__PROC__/n2/g' \
    k8s/overlays/boutique.kustomization.tmpl.yaml > "$d/kustomization.yaml"
  kubectl kustomize "$d" >/dev/null 2>&1 || { red "overlay build failed"; ok=0; fail=1; }
  rm -rf "$d"
  kubectl kustomize k8s/base >/dev/null 2>&1 || { red "base build failed"; ok=0; fail=1; }
  [ "$ok" = "1" ] && grn "kustomize ok"
else missing kubectl; fi

sec "result"
if [ "$fail" = "0" ]; then grn "ALL CHECKS PASSED"; else red "VALIDATION FAILED"; fi
exit "$fail"
