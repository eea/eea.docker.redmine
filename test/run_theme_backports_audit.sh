#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH_CANDIDATES=(
  "${NPX_BIN:-}"
  "$(command -v npx 2>/dev/null || true)"
  "/Users/silviu/.nvs/default/bin/npx"
  "/opt/homebrew/bin/npx"
  "/usr/local/bin/npx"
)

NPX_CMD=""
for candidate in "${PATH_CANDIDATES[@]}"; do
  if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
    NPX_CMD="${candidate}"
    break
  fi
done

if [ -z "${NPX_CMD}" ]; then
  echo "npx not found. Set NPX_BIN or add npx to PATH." >&2
  exit 1
fi

NODE_BIN_DIR="$(dirname "${NPX_CMD}")"
export PATH="${NODE_BIN_DIR}:${PATH}"

mkdir -p "${ROOT_DIR}/output/playwright"

cd "${ROOT_DIR}"
exec "${NPX_CMD}" -y -p playwright node test/theme_backports_audit.js
