#!/bin/bash
set -euo pipefail

log_info() {
  echo "[runtime] $*"
}

log_warn() {
  echo "[runtime][warn] $*" >&2
}

log_error() {
  echo "[runtime][error] $*" >&2
}

safe_rm_path() {
  local target="$1"
  [ -e "${target}" ] || return 0
  rm -f "${target}" || true
}

retry_with_backoff() {
  local retries="$1"
  local delay="$2"
  shift 2

  local attempt=1
  while [ "${attempt}" -le "${retries}" ]; do
    if "$@"; then
      return 0
    fi
    if [ "${attempt}" -eq "${retries}" ]; then
      return 1
    fi
    sleep "${delay}"
    attempt=$((attempt + 1))
  done
}
