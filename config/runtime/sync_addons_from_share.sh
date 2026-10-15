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
TMP_ROOT="${ADDONS_VOLUME_ROOT}/.sync-tmp-share"

PLUGINS_URL=${PLUGINS_URL:-}
ADDONS_BASE_URL=${ADDONS_BASE_URL:-}
PLUGINS_USER=${PLUGINS_USER:-}
PLUGINS_PASSWORD=${PLUGINS_PASSWORD:-}
A1_THEME_URL=${A1_THEME_URL:-}
A1_THEME_ZIP=${A1_THEME_ZIP:-}
A1_THEME_ID=${A1_THEME_ID:-a1}
ADDONS_SYNC_SKIP_IF_PRESENT=${ADDONS_SYNC_SKIP_IF_PRESENT:-1}
ADDONS_DOWNLOAD_ATTEMPTS=${ADDONS_DOWNLOAD_ATTEMPTS:-3}
ADDONS_DOWNLOAD_CONNECT_TIMEOUT=${ADDONS_DOWNLOAD_CONNECT_TIMEOUT:-10}
ADDONS_DOWNLOAD_MAX_TIME=${ADDONS_DOWNLOAD_MAX_TIME:-120}
ADDONS_DOWNLOAD_RETRY_DELAY=${ADDONS_DOWNLOAD_RETRY_DELAY:-5}
ADDONS_DOWNLOAD_CONCURRENCY=${ADDONS_DOWNLOAD_CONCURRENCY:-4}
# Share metadata snapshot produced by the hook job's PROPFIND probe: one TSV row
# per pinned archive, "<location>\t<archive>\t<etag>\t<size>\t<mtime>". The share
# etag is content-derived by Nextcloud, so etag+size is a reliable change signal
# and size lets us verify downloads byte-exact. When absent, the legacy behavior
# (re-download everything) applies.
ADDONS_REMOTE_META=${ADDONS_REMOTE_META:-}
if [ -n "${ADDONS_REMOTE_META}" ] && [ -s "${ADDONS_REMOTE_META}" ]; then
  meta_mode=1
else
  meta_mode=0
fi

addons_cfg="${REDMINE_PATH:-/usr/src/redmine}/addons.cfg"
addons_manifest="${addons_cfg}"
addons_base_url=""
plugins_dst="${ADDONS_CURRENT_DIR}/plugins"
themes_dst="${ADDONS_CURRENT_DIR}/themes"
plugins_tmp="${TMP_ROOT}/plugins"
themes_tmp="${TMP_ROOT}/themes"
cache_root="${TMP_ROOT}/by-hash"
index_file="${TMP_ROOT}/INDEX"
# Per-volume store of the share metadata last verified into this volume, TSV:
# <location>\t<archive>\t<etag>\t<size>\t<mtime>.
meta_store="${ADDONS_VOLUME_ROOT}/.addons-remote-meta.tsv"

mkdir -p "${plugins_dst}" "${themes_dst}" "${plugins_tmp}" "${themes_tmp}" "${cache_root}"

if [ ! -f "${addons_manifest}" ]; then
  log_error "addons.cfg not found: ${addons_manifest}"
  exit 1
fi

if [ -n "${ADDONS_BASE_URL}" ]; then
  addons_base_url="${ADDONS_BASE_URL%/}"
elif [ -n "${PLUGINS_URL}" ]; then
  addons_base_url="${PLUGINS_URL%/plugins}"
else
  log_error "ADDONS_BASE_URL or PLUGINS_URL is required for share sync"
  exit 1
fi

manifest_cmd=(ruby /usr/src/redmine/config/lib/addons_manifest.rb)
if [ ! -x /usr/src/redmine/config/lib/addons_manifest.rb ] && [ -f "${REDMINE_PATH:-/usr/src/redmine}/config/lib/addons_manifest.rb" ]; then
  manifest_cmd=(ruby "${REDMINE_PATH:-/usr/src/redmine}/config/lib/addons_manifest.rb")
fi

addons_already_synced() {
  local kind="" name="" location="" archive=""

  [ -d "${themes_dst}/${A1_THEME_ID}" ] || return 1

  while IFS=: read -r kind name location archive; do
    [ "${kind}" = "plugin" ] || continue
    [ -d "${plugins_dst}/${name}" ] || return 1
  done < <("${manifest_cmd[@]}" list)

  return 0
}

clean_dir() {
  local dir="$1"
  find "${dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

# INDEX line format: <sha256>  <kind>:<name>:<location>:<archive>
index_lookup() {
  local kind="$1" name="$2"
  [ -f "${index_file}" ] || return 1
  awk -v k="${kind}" -v n="${name}" '{ split($2, a, ":"); if (a[1] == k && a[2] == n) { print $1; exit } }' "${index_file}"
}

index_upsert() {
  local sha="$1" kind="$2" name="$3" location="$4" archive="$5" tmp=""
  tmp="$(mktemp)"
  awk -v k="${kind}" -v n="${name}" '{ split($2, a, ":"); if (a[1] == k && a[2] == n) next; print }' "${index_file}" > "${tmp}" 2>/dev/null || true
  printf '%s  %s:%s:%s:%s\n' "${sha}" "${kind}" "${name}" "${location}" "${archive}" >> "${tmp}"
  mv "${tmp}" "${index_file}"
}

index_prune() {
  [ -f "${index_file}" ] || return 0
  local f="" h=""
  find "${cache_root}" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' f; do
    h="$(basename "${f}")"
    grep -qF "${h}  " "${index_file}" || rm -f "${f}"
  done
}

meta_lookup() {
  local location="$1" archive="$2"
  [ -f "${meta_store}" ] || return 1
  awk -F'\t' -v l="${location}" -v a="${archive}" '$1 == l && $2 == a { print; exit }' "${meta_store}"
}

# Replace (not append) the row for (location, archive) so stale rows can never
# shadow the verified one.
meta_store_upsert() {
  local location="$1" archive="$2" etag="$3" size="$4" mtime="$5" tmp=""
  tmp="$(mktemp)"
  awk -F'\t' -v l="${location}" -v a="${archive}" '{ if ($1 == l && $2 == a) next; print }' "${meta_store}" > "${tmp}" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\n' "${location}" "${archive}" "${etag}" "${size}" "${mtime}" >> "${tmp}"
  mv "${tmp}" "${meta_store}"
}

# Returns 0 when the entry's share metadata matches the per-volume store, the
# by-hash cache is intact and the destination marker points at it.
meta_entry_current() {
  local kind="$1" name="$2" location="$3" archive="$4" etag="$5" size="$6"
  local stored="" s_etag="" s_size="" known_sha="" dest=""

  stored="$(meta_lookup "${location}" "${archive}" || true)"
  [ -n "${stored}" ] || return 1
  s_etag="$(cut -f3 <<<"${stored}")"
  s_size="$(cut -f4 <<<"${stored}")"
  [ "${s_etag}" = "${etag}" ] && [ "${s_size}" = "${size}" ] || return 1

  known_sha="$(index_lookup "${kind}" "${name}" || true)"
  [ -n "${known_sha}" ] || return 1
  [ -f "${cache_root}/${known_sha}" ] || return 1

  if [ "${kind}" = "plugin" ]; then
    dest="${plugins_dst}/${name}"
  else
    dest="${themes_dst}/${A1_THEME_ID}"
  fi
  [ -f "${dest}/.addons-sha256" ] || return 1
  [ "$(cat "${dest}/.addons-sha256")" = "${known_sha}" ] || return 1
  return 0
}

download_file() {
  local url="$1"
  local destination="$2"
  local attempt=""

  for attempt in $(seq 1 "${ADDONS_DOWNLOAD_ATTEMPTS}"); do
    if command -v curl >/dev/null 2>&1; then
      if [ -n "${PLUGINS_USER}" ]; then
        curl -fsSL \
          --connect-timeout "${ADDONS_DOWNLOAD_CONNECT_TIMEOUT}" \
          --max-time "${ADDONS_DOWNLOAD_MAX_TIME}" \
          -u "${PLUGINS_USER}:${PLUGINS_PASSWORD}" \
          -o "${destination}.part" "${url}" < /dev/null && break
      else
        curl -fsSL \
          --connect-timeout "${ADDONS_DOWNLOAD_CONNECT_TIMEOUT}" \
          --max-time "${ADDONS_DOWNLOAD_MAX_TIME}" \
          -o "${destination}.part" "${url}" < /dev/null && break
      fi
    elif command -v wget >/dev/null 2>&1; then
      if [ -n "${PLUGINS_USER}" ]; then
        wget -q --tries=1 \
          --connect-timeout="${ADDONS_DOWNLOAD_CONNECT_TIMEOUT}" \
          --timeout="${ADDONS_DOWNLOAD_MAX_TIME}" \
          --user="${PLUGINS_USER}" --password="${PLUGINS_PASSWORD}" \
          -O "${destination}.part" "${url}" < /dev/null && break
      else
        wget -q --tries=1 \
          --connect-timeout="${ADDONS_DOWNLOAD_CONNECT_TIMEOUT}" \
          --timeout="${ADDONS_DOWNLOAD_MAX_TIME}" \
          -O "${destination}.part" "${url}" < /dev/null && break
      fi
    else
      log_error "Neither wget nor curl is available"
      exit 1
    fi
    rm -f "${destination}.part"
    echo "Download attempt ${attempt}/${ADDONS_DOWNLOAD_ATTEMPTS} failed for ${url}"
    [ "${attempt}" -lt "${ADDONS_DOWNLOAD_ATTEMPTS}" ] && sleep "${ADDONS_DOWNLOAD_RETRY_DELAY}"
  done

  [ -s "${destination}.part" ] || {
    log_error "Download failed after ${ADDONS_DOWNLOAD_ATTEMPTS} attempts: ${url}"
    rm -f "${destination}.part"
    return 1
  }
  mv "${destination}.part" "${destination}"
}

# Download (if needed) and return the cache sha for one manifest entry.
# Populates by-hash cache + INDEX; verifies content against the expected sha
# when one is known (share-side addons.sha256).
ensure_cached() {
  local kind="$1" name="$2" location="$3" archive="$4" expected_sha="$5"
  local url="$6"
  local known_sha="" archive_tmp="" actual_sha=""

  # Cache hit is only safe when the cached content is verified against a known
  # expected hash (share-side manifest). In legacy mode (no expected_sha) the sync
  # was triggered by a remote change, so we must re-download; the cache is still
  # rebuilt afterwards for resumability across retries.
  known_sha="$(index_lookup "${kind}" "${name}" || true)"
  if [ -n "${expected_sha}" ] && [ "${known_sha}" = "${expected_sha}" ] && [ -f "${cache_root}/${known_sha}" ]; then
    CACHE_RESULT="${known_sha}"
    return 0
  fi
  if [ -n "${expected_sha}" ] && [ -n "${known_sha}" ] && [ "${known_sha}" != "${expected_sha}" ]; then
    echo "Cached ${kind} ${name} content changed (INDEX ${known_sha:0:12}... != manifest ${expected_sha:0:12}...); re-downloading"
  fi

  archive_flat="${archive//\//_}"
  archive_tmp="${TMP_ROOT}/dl-${name}-${archive_flat}"
  if [ -s "${archive_tmp}" ]; then
    echo "Reusing pre-downloaded ${kind} ${name} (${archive})"
  else
    echo "Downloading ${kind} ${name} from ${url}"
    if ! download_file "${url}" "${archive_tmp}"; then
      return 1
    fi
  fi
  actual_sha="$(sha256_of "${archive_tmp}")"

  if [ -n "${expected_sha}" ] && [ "${actual_sha}" != "${expected_sha}" ]; then
    rm -f "${archive_tmp}"
    log_error "sha256 mismatch for ${kind} ${name} (${archive}): expected ${expected_sha}, got ${actual_sha}"
    exit 1
  fi
  if [ -z "${expected_sha}" ]; then
    unzip -tqq "${archive_tmp}"
  fi

  install -m 0644 "${archive_tmp}" "${cache_root}/${actual_sha}"
  rm -f "${archive_tmp}"
  index_upsert "${actual_sha}" "${kind}" "${name}" "${location}" "${archive}"
  CACHE_RESULT="${actual_sha}"
  echo "Cached ${kind} ${name} (${archive}) sha256=${actual_sha:0:12}..."
  return 0
}

extract_plugin() {
  local name="$1" cache_sha="$2"
  local dest="${plugins_dst}/${name}"
  local scratch="${plugins_tmp}/${name}.extract"
  local candidate=""

  if [ -f "${dest}/.addons-sha256" ] && [ "$(cat "${dest}/.addons-sha256")" = "${cache_sha}" ]; then
    return 0
  fi

  echo "Extracting plugin ${name} (sha256=${cache_sha:0:12}...)"
  rm -rf "${scratch}"
  mkdir -p "${scratch}"
  unzip -q -o "${cache_root}/${cache_sha}" -d "${scratch}"
  if [ ! -d "${scratch}/${name}" ]; then
    candidate="$(find "${scratch}" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/init.rb' \; -print | head -n 1 || true)"
    if [ -n "${candidate}" ]; then
      mv "${candidate}" "${scratch}/${name}"
    fi
  fi
  if [ ! -d "${scratch}/${name}" ]; then
    rm -rf "${scratch}"
    log_error "Plugin directory ${name} not found after extraction"
    exit 1
  fi
  rm -rf "${dest}"
  mv "${scratch}/${name}" "${dest}"
  printf '%s\n' "${cache_sha}" > "${dest}/.addons-sha256"
  rm -rf "${scratch}"
  CHANGED=1
  return 0
}

extract_theme() {
  local name="$1" cache_sha="$2"
  local dest="${themes_dst}/${A1_THEME_ID}"
  local scratch="${themes_tmp}/theme.extract"
  local candidate=""

  if [ -f "${dest}/.addons-sha256" ] && [ "$(cat "${dest}/.addons-sha256")" = "${cache_sha}" ]; then
    return 0
  fi

  echo "Extracting ${A1_THEME_ID} theme (sha256=${cache_sha:0:12}...)"
  rm -rf "${scratch}"
  mkdir -p "${scratch}"
  unzip -q -o "${cache_root}/${cache_sha}" -d "${scratch}"
  if [ ! -d "${scratch}/${A1_THEME_ID}" ]; then
    candidate="$(find "${scratch}" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
    if [ -n "${candidate}" ] && [ -f "${candidate}/stylesheets/application.css" ]; then
      mv "${candidate}" "${scratch}/${A1_THEME_ID}"
    fi
  fi
  if [ ! -d "${scratch}/${A1_THEME_ID}" ]; then
    rm -rf "${scratch}"
    log_error "A1 theme directory not found after extraction: ${scratch}/${A1_THEME_ID}"
    exit 1
  fi
  rm -rf "${dest}"
  mv "${scratch}/${A1_THEME_ID}" "${dest}"
  printf '%s\n' "${cache_sha}" > "${dest}/.addons-sha256"
  rm -rf "${scratch}"
  CHANGED=1
  return 0
}

if [ "${ADDONS_SYNC_SKIP_IF_PRESENT}" = "1" ] && addons_already_synced; then
  echo "Addons already present in ${ADDONS_CURRENT_DIR}, skipping share download"
  exit 0
fi

clean_dir "${plugins_tmp}"
clean_dir "${themes_tmp}"

CHANGED=0

if [ "${meta_mode}" = "1" ]; then
  echo "Using share metadata snapshot (PROPFIND probe): ${ADDONS_REMOTE_META}"
else
  echo "No share metadata snapshot available; falling back to full re-download probing"
fi

# Desired entries: kind \t name \t location \t archive \t etag \t size \t mtime
# (the last three are populated only in metadata mode)
entries_file="$(mktemp)"
trap 'rm -f "${entries_file}"' EXIT
while IFS=: read -r kind name location archive; do
  [ -n "${kind}" ] || continue
  case "${kind}" in
    "#"*) continue ;;
  esac
  [ -n "${name}" ] && [ -n "${location}" ] && [ -n "${archive}" ] || continue
  case "${kind}" in
    plugin | theme) ;;
    *) echo "Ignoring addons.cfg entry with unknown kind '${kind}': ${name}"; continue ;;
  esac
  expected_etag=""
  expected_size=""
  expected_mtime=""
  if [ "${meta_mode}" = "1" ]; then
    row="$(awk -F'\t' -v l="${location}" -v a="${archive}" '$1 == l && $2 == a { print $3 "\t" $4 "\t" $5; exit }' "${ADDONS_REMOTE_META}")"
    if [ -n "${row}" ]; then
      IFS=$'\t' read -r expected_etag expected_size expected_mtime <<< "${row}"
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${kind}" "${name}" "${location}" "${archive}" "${expected_etag}" "${expected_size}" "${expected_mtime}" >> "${entries_file}"
done < "${addons_cfg}"

[ -s "${entries_file}" ] || {
  log_error "No addons entries resolved from ${addons_cfg}"
  exit 1
}

# Metadata mode: fetch every entry that is not already current, in parallel.
# Files land at the paths ensure_cached reuses; the share size is verified here,
# before the serial verify/extract phase.
if [ "${meta_mode}" = "1" ]; then
  dl_list_file="$(mktemp)"
  trap 'rm -f "${entries_file}" "${dl_list_file}"' EXIT
  while IFS=$'\t' read -r kind name location archive expected_etag expected_size expected_mtime; do
    [ -n "${kind}" ] || continue
    if [ -z "${expected_etag}" ] || [ -z "${expected_size}" ]; then
      log_error "Metadata mode: no share metadata for ${kind} ${name} (${location}/${archive})"
      exit 1
    fi
    if meta_entry_current "${kind}" "${name}" "${location}" "${archive}" "${expected_etag}" "${expected_size}"; then
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "${location}" "${archive}" "${name}" "${expected_size}" >> "${dl_list_file}"
  done < "${entries_file}"

  dl_failed=0
  dl_count=0
  dl_pids=()
  while IFS=$'\t' read -r location archive name expected_size; do
    [ -n "${archive}" ] || continue
    archive_flat="${archive//\//_}"
    pre_dest="${TMP_ROOT}/dl-${name}-${archive_flat}"
    (
      if [ -s "${pre_dest}" ]; then
        exit 0
      fi
      if download_file "${addons_base_url}/${location}/${archive}" "${pre_dest}"; then
        pre_size="$(wc -c < "${pre_dest}" 2>/dev/null | awk '{print $1}')"
        if [ "${pre_size}" = "${expected_size}" ]; then
          exit 0
        fi
        echo "Size mismatch for ${location}/${archive}: expected ${expected_size}, got ${pre_size}" >&2
      fi
      exit 1
    ) &
    dl_pids+=("$!")
    dl_count=$((dl_count + 1))
    if [ "${dl_count}" -ge "${ADDONS_DOWNLOAD_CONCURRENCY}" ]; then
      for pid in "${dl_pids[@]}"; do
        wait "${pid}" || dl_failed=1
      done
      dl_count=0
      dl_pids=()
    fi
  done < "${dl_list_file}"
  if [ "${dl_count}" -gt 0 ]; then
    for pid in "${dl_pids[@]}"; do
      wait "${pid}" || dl_failed=1
    done
  fi
  if [ "${dl_failed}" != "0" ]; then
    log_error "Parallel share download failed"
    exit 1
  fi
fi

while IFS=$'\t' read -r kind name location archive expected_etag expected_size expected_mtime; do
  [ -n "${kind}" ] || continue

  if [ "${meta_mode}" = "1" ]; then
    if meta_entry_current "${kind}" "${name}" "${location}" "${archive}" "${expected_etag}" "${expected_size}"; then
      echo "Up to date: ${kind} ${name} (etag=${expected_etag:0:12}...)"
      continue
    fi
    echo "Changed: ${kind} ${name} (share etag=${expected_etag:0:12}... size=${expected_size})"
  fi

  if [ "${kind}" = "theme" ] && [ -n "${A1_THEME_URL}" ]; then
    url="${A1_THEME_URL%/}"
  else
    url="${addons_base_url}/${location}/${archive}"
  fi

  CACHE_RESULT=""
  if ! ensure_cached "${kind}" "${name}" "${location}" "${archive}" "" "${url}"; then
    log_error "Failed to fetch ${kind} ${name} from share"
    exit 1
  fi

  if [ "${kind}" = "plugin" ]; then
    extract_plugin "${name}" "${CACHE_RESULT}"
  else
    extract_theme "${name}" "${CACHE_RESULT}"
  fi

  if [ "${meta_mode}" = "1" ]; then
    meta_store_upsert "${location}" "${archive}" "${expected_etag}" "${expected_size}" "${expected_mtime}"
  fi
done < "${entries_file}"

index_prune

# In full mode the destination must match the manifest exactly: remove plugin
# directories that are no longer listed in addons.cfg. Additive mode preserves
# them (per-plugin extraction never touches non-manifest dirs).
if [ "${ADDONS_SYNC_MODE:-full}" = "full" ]; then
  manifest_plugin_names=""
  while IFS=$'\t' read -r ekind ename elocation earchive esa; do
    [ "${ekind}" = "plugin" ] || continue
    manifest_plugin_names="${manifest_plugin_names}${ename}"$'\n'
  done < "${entries_file}"
  for dir in "${plugins_dst}"/*/; do
    [ -d "${dir}" ] || continue
    dname="$(basename "${dir}")"
    if ! printf '%s' "${manifest_plugin_names}" | grep -qxF "${dname}"; then
      echo "[full] Removing plugin not in manifest: ${dname}"
      rm -rf "${dir}"
      CHANGED=1
    fi
  done
fi
clean_dir "${plugins_tmp}"
clean_dir "${themes_tmp}"

find "${plugins_dst}" -mindepth 2 -maxdepth 2 -name Gemfile -delete
find "${plugins_dst}" -name '.DS_Store' -delete
find "${themes_dst}" -name '.DS_Store' -delete

if [ "${CHANGED}" = "1" ]; then
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
fi

log_info "Share addons normalized into ${ADDONS_CURRENT_DIR}"
