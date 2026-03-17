#!/bin/bash
set -euo pipefail

if [ -f /usr/local/bin/common.sh ]; then
  # shellcheck disable=SC1091
  source /usr/local/bin/common.sh
fi
type log_info >/dev/null 2>&1 || log_info() { echo "[runtime] $*"; }
type log_error >/dev/null 2>&1 || log_error() { echo "[runtime][error] $*" >&2; }

ADDONS_VOLUME_ROOT=${ADDONS_VOLUME_ROOT:-/addons}
ADDONS_CURRENT_DIR="${ADDONS_VOLUME_ROOT}/current"
SEED_ROOT=${SEED_ROOT:-/seed}
TMP_ROOT="${ADDONS_VOLUME_ROOT}/.sync-tmp"

plugins_src="${SEED_ROOT}/plugins"
themes_src="${SEED_ROOT}/themes"
plugins_dst="${ADDONS_CURRENT_DIR}/plugins"
themes_dst="${ADDONS_CURRENT_DIR}/themes"
plugins_tmp="${TMP_ROOT}/plugins"
themes_tmp="${TMP_ROOT}/themes"

mkdir -p "${plugins_dst}" "${themes_dst}" "${plugins_tmp}" "${themes_tmp}"

if [ ! -d "${plugins_src}" ] || [ ! -d "${themes_src}" ]; then
  log_error "Seed directories ${plugins_src} and ${themes_src} are required"
  exit 1
fi

clean_dir() {
  local dir="$1"
  find "${dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

copy_tree() {
  local source="$1"
  local destination_root="$2"
  local name

  name="$(basename "${source}")"
  [ "${name}" = ".DS_Store" ] && return 0
  cp -a "${source}" "${destination_root}/"
  find "${destination_root}/${name}" -name '.DS_Store' -delete
}

unpack_zip() {
  local archive="$1"
  local destination_root="$2"
  local scratch_dir

  scratch_dir="$(mktemp -d "${TMP_ROOT}/unzip.XXXXXX")"
  unzip -q -o "${archive}" -d "${scratch_dir}"
  find "${scratch_dir}" -name '.DS_Store' -delete

  shopt -s nullglob dotglob
  for entry in "${scratch_dir}"/*; do
    [ -e "${entry}" ] || continue
    copy_tree "${entry}" "${destination_root}"
  done
  shopt -u nullglob dotglob

  rm -rf "${scratch_dir}"
}

sync_seed_dir() {
  local source_root="$1"
  local destination_root="$2"
  local entry

  clean_dir "${destination_root}"

  shopt -s nullglob dotglob
  for entry in "${source_root}"/*; do
    [ -e "${entry}" ] || continue
    case "${entry}" in
      *.zip)
        unpack_zip "${entry}" "${destination_root}"
        ;;
      *)
        copy_tree "${entry}" "${destination_root}"
        ;;
    esac
  done
  shopt -u nullglob dotglob
}

clean_dir "${plugins_tmp}"
clean_dir "${themes_tmp}"

sync_seed_dir "${plugins_src}" "${plugins_tmp}"
sync_seed_dir "${themes_src}" "${themes_tmp}"

clean_dir "${plugins_dst}"
clean_dir "${themes_dst}"

cp -a "${plugins_tmp}/." "${plugins_dst}/"
cp -a "${themes_tmp}/." "${themes_dst}/"

find "${plugins_dst}" -mindepth 2 -maxdepth 2 -name Gemfile -delete
find "${plugins_dst}" -name '.DS_Store' -delete
find "${themes_dst}" -name '.DS_Store' -delete

if [ -x /usr/local/bin/apply_a1_theme_overrides.sh ] && [ -d "${themes_dst}/a1" ]; then
  THEMES_DIR="${themes_dst}" A1_THEME_ID="${A1_THEME_ID:-a1}" /usr/local/bin/apply_a1_theme_overrides.sh
fi

if [ -x /usr/local/bin/prepare_addons_assets.sh ]; then
  ADDONS_CURRENT_DIR="${ADDONS_CURRENT_DIR}" \
  PLUGINS_DIR="${plugins_dst}" \
  THEMES_DIR="${themes_dst}" \
  A1_THEME_ID="${A1_THEME_ID:-a1}" \
  /usr/local/bin/prepare_addons_assets.sh
fi

log_info "Seed addons normalized from ${SEED_ROOT} into ${ADDONS_CURRENT_DIR}"
