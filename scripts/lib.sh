#!/usr/bin/env bash
# Shared helpers. Source from other scripts. The single source of truth for the
# platform selection is config/platforms.json (also read by Terraform).
# Requires: python3 (stdlib only).

# REPO_ROOT must be set by the caller; default to the repo containing this file.
: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${CONFIG_FILE:=${REPO_ROOT}/config/platforms.json}"

# The 2 selected platform keys, space-separated (e.g. "n2 c3").
platforms_selected() {
  python3 -c "import json;print(' '.join(json.load(open('${CONFIG_FILE}'))['selected']))"
}

# Human label for a platform key (e.g. "Intel Sapphire Rapids").
platform_label() {
  python3 -c "import json;print(json.load(open('${CONFIG_FILE}'))['catalog']['$1']['label'])"
}

# Machine type for a platform key (e.g. "c3-standard-4").
platform_machine_type() {
  python3 -c "import json;print(json.load(open('${CONFIG_FILE}'))['catalog']['$1']['machine_type'])"
}
