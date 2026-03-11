#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
LOGIN_USER="${LOGIN_USER:-admin}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-Admin123!}"
TARGET_PATH="${TARGET_PATH:-/my/page}"
REQUESTS="${REQUESTS:-30}"
LOGIN_REQUESTS="${LOGIN_REQUESTS:-10}"

cookie_file="$(mktemp)"
trap 'rm -f "${cookie_file}"' EXIT

extract_auth_token() {
  sed -n 's/.*name="authenticity_token" value="\([^"]*\)".*/\1/p' | head -n1
}

extract_meta_csrf_token() {
  sed -n 's/.*name="csrf-token" content="\([^"]*\)".*/\1/p' | head -n1
}

run_login() {
  local login_page auth_token
  login_page="$(curl -fsS -c "${cookie_file}" "${BASE_URL}/login")"
  auth_token="$(printf '%s' "${login_page}" | extract_auth_token)"
  if [ -z "${auth_token}" ]; then
    auth_token="$(printf '%s' "${login_page}" | extract_meta_csrf_token)"
  fi

  if [ -n "${auth_token}" ]; then
    curl -fsS -L -o /dev/null -w '%{time_total}\n' -b "${cookie_file}" -c "${cookie_file}" \
      --data-urlencode "authenticity_token=${auth_token}" \
      --data-urlencode "username=${LOGIN_USER}" \
      --data-urlencode "password=${LOGIN_PASSWORD}" \
      --data-urlencode "login=Login" \
      "${BASE_URL}/login"
    return 0
  fi

  curl -fsS -L -o /dev/null -w '%{time_total}\n' -b "${cookie_file}" -c "${cookie_file}" \
    --data-urlencode "username=${LOGIN_USER}" \
    --data-urlencode "password=${LOGIN_PASSWORD}" \
    --data-urlencode "login=Login" \
    "${BASE_URL}/login"
}

summarize_times() {
  local label="$1"
  local file="$2"
  awk -v label="${label}" '
    { sum += $1; if (NR == 1 || $1 < min) min = $1; if ($1 > max) max = $1 }
    END {
      if (NR == 0) { exit 1 }
      printf "%s count=%d avg=%.4fs min=%.4fs max=%.4fs\n", label, NR, sum/NR, min, max
    }
  ' "${file}"
}

login_times_file="$(mktemp)"
times_file="$(mktemp)"
trap 'rm -f "${cookie_file}" "${login_times_file}" "${times_file}"' EXIT

for _ in $(seq 1 "${LOGIN_REQUESTS}"); do
  : > "${cookie_file}"
  run_login >> "${login_times_file}"
done

: > "${cookie_file}"
run_login >/dev/null

if ! curl -fsS -o /dev/null -b "${cookie_file}" "${BASE_URL}${TARGET_PATH}"; then
  echo "Authenticated request failed for ${TARGET_PATH}"
  exit 1
fi

for _ in $(seq 1 "${REQUESTS}"); do
  curl -fsS -o /dev/null -w '%{time_total}\n' -b "${cookie_file}" "${BASE_URL}${TARGET_PATH}" >> "${times_file}"
done

summarize_times "login" "${login_times_file}"
summarize_times "target" "${times_file}"
