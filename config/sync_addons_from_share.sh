#!/bin/bash
set -euo pipefail

ADDONS_VOLUME_ROOT=${ADDONS_VOLUME_ROOT:-/addons}
ADDONS_CURRENT_DIR="${ADDONS_VOLUME_ROOT}/current"
TMP_ROOT="${ADDONS_VOLUME_ROOT}/.sync-tmp-share"

PLUGINS_URL=${PLUGINS_URL:-}
PLUGINS_USER=${PLUGINS_USER:-}
PLUGINS_PASSWORD=${PLUGINS_PASSWORD:-}
A1_THEME_URL=${A1_THEME_URL:-}
A1_THEME_ZIP=${A1_THEME_ZIP:-a1_theme-4_1_2.zip}
A1_THEME_ID=${A1_THEME_ID:-a1}
ADDONS_SYNC_SKIP_IF_PRESENT=${ADDONS_SYNC_SKIP_IF_PRESENT:-1}

plugins_cfg="${REDMINE_PATH:-/usr/src/redmine}/plugins.cfg"
plugins_dst="${ADDONS_CURRENT_DIR}/plugins"
themes_dst="${ADDONS_CURRENT_DIR}/themes"
plugins_tmp="${TMP_ROOT}/plugins"
themes_tmp="${TMP_ROOT}/themes"

mkdir -p "${plugins_dst}" "${themes_dst}" "${plugins_tmp}" "${themes_tmp}"

if [ -z "${PLUGINS_URL}" ]; then
  echo "PLUGINS_URL is required for share sync" >&2
  exit 1
fi

if [ ! -f "${plugins_cfg}" ]; then
  echo "plugins.cfg not found: ${plugins_cfg}" >&2
  exit 1
fi

addons_already_synced() {
  local plugin_name=""
  local plugin_file=""

  [ -d "${themes_dst}/${A1_THEME_ID}" ] || return 1

  while IFS=: read -r plugin_name plugin_file; do
    [ -n "${plugin_name}" ] || continue
    [ -d "${plugins_dst}/${plugin_name}" ] || return 1
  done < "${plugins_cfg}"

  return 0
}

clean_dir() {
  local dir="$1"
  find "${dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

download_file() {
  local url="$1"
  local destination="$2"

  if command -v wget >/dev/null 2>&1; then
    if [ -n "${PLUGINS_USER}" ]; then
      wget -q --user="${PLUGINS_USER}" --password="${PLUGINS_PASSWORD}" -O "${destination}" "${url}"
    else
      wget -q -O "${destination}" "${url}"
    fi
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    if [ -n "${PLUGINS_USER}" ]; then
      curl -fsSL -u "${PLUGINS_USER}:${PLUGINS_PASSWORD}" -o "${destination}" "${url}"
    else
      curl -fsSL -o "${destination}" "${url}"
    fi
    return 0
  fi

  echo "Neither wget nor curl is available" >&2
  exit 1
}

normalize_theme_dir() {
  if [ -d "${themes_tmp}/${A1_THEME_ID}" ]; then
    return 0
  fi

  local candidate=""
  candidate="$(find "${themes_tmp}" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
  if [ -n "${candidate}" ] && [ -f "${candidate}/stylesheets/application.css" ]; then
    mv "${candidate}" "${themes_tmp}/${A1_THEME_ID}"
  fi
}

if [ "${ADDONS_SYNC_SKIP_IF_PRESENT}" = "1" ] && addons_already_synced; then
  echo "Addons already present in ${ADDONS_CURRENT_DIR}, skipping share download"
  exit 0
fi

clean_dir "${plugins_tmp}"
clean_dir "${themes_tmp}"

while IFS=: read -r plugin_name plugin_file; do
  [ -n "${plugin_name}" ] || continue
  [ -n "${plugin_file}" ] || continue

  archive="${TMP_ROOT}/${plugin_file}"
  download_url="${PLUGINS_URL%/}/${plugin_file}"
  echo "Downloading plugin ${plugin_name} from ${download_url}"
  download_file "${download_url}" "${archive}"
  unzip -tqq "${archive}"
  unzip -q -o "${archive}" -d "${plugins_tmp}"
done < "${plugins_cfg}"

theme_download_url="${A1_THEME_URL:-${PLUGINS_URL%/plugins}/themes/${A1_THEME_ZIP}}"
theme_archive="${TMP_ROOT}/${A1_THEME_ZIP}"
echo "Downloading theme from ${theme_download_url}"
download_file "${theme_download_url}" "${theme_archive}"
unzip -tqq "${theme_archive}"
unzip -q -o "${theme_archive}" -d "${themes_tmp}"
normalize_theme_dir

if [ ! -d "${themes_tmp}/${A1_THEME_ID}" ]; then
  echo "A1 theme directory not found after extraction: ${themes_tmp}/${A1_THEME_ID}" >&2
  exit 1
fi

clean_dir "${plugins_dst}"
clean_dir "${themes_dst}"

cp -a "${plugins_tmp}/." "${plugins_dst}/"
cp -a "${themes_tmp}/." "${themes_dst}/"

find "${plugins_dst}" -mindepth 2 -maxdepth 2 -name Gemfile -delete
find "${plugins_dst}" -name '.DS_Store' -delete
find "${themes_dst}" -name '.DS_Store' -delete

if [ -x /usr/local/bin/apply_a1_theme_overrides.sh ] && [ -d "${themes_dst}/${A1_THEME_ID}" ]; then
  THEMES_DIR="${themes_dst}" A1_THEME_ID="${A1_THEME_ID}" /usr/local/bin/apply_a1_theme_overrides.sh
fi

if [ -x /usr/local/bin/prepare_addons_assets.sh ]; then
  ADDONS_CURRENT_DIR="${ADDONS_CURRENT_DIR}" \
  PLUGINS_DIR="${plugins_dst}" \
  THEMES_DIR="${themes_dst}" \
  A1_THEME_ID="${A1_THEME_ID}" \
  /usr/local/bin/prepare_addons_assets.sh
fi

echo "Share addons normalized into ${ADDONS_CURRENT_DIR}"
