#!/bin/bash
set -euo pipefail

ADDONS_VOLUME_ROOT=${ADDONS_VOLUME_ROOT:-/addons}
ADDONS_RELEASES_DIR="${ADDONS_VOLUME_ROOT}/releases"
ADDONS_CURRENT_LINK="${ADDONS_VOLUME_ROOT}/current"
ADDONS_STATE_DIR="${ADDONS_VOLUME_ROOT}/state"
ADDONS_VERSION_FILE="${ADDONS_STATE_DIR}/version"
ADDONS_ARCHIVE_URL=${ADDONS_ARCHIVE_URL:-}
ADDONS_VERSION=${ADDONS_VERSION:-}
ADDONS_SHA256=${ADDONS_SHA256:-}
ADDONS_USER=${ADDONS_USER:-${PLUGINS_USER:-}}
ADDONS_PASSWORD=${ADDONS_PASSWORD:-${PLUGINS_PASSWORD:-}}
TMP_DIR=${TMP_DIR:-/tmp/addons-sync}

if [ -z "${ADDONS_ARCHIVE_URL}" ]; then
  echo "ADDONS_ARCHIVE_URL is required" >&2
  exit 1
fi

if [ -z "${ADDONS_VERSION}" ]; then
  echo "ADDONS_VERSION is required" >&2
  exit 1
fi

mkdir -p "${ADDONS_RELEASES_DIR}" "${ADDONS_STATE_DIR}" "${TMP_DIR}"

current_version=""
if [ -f "${ADDONS_VERSION_FILE}" ]; then
  current_version="$(cat "${ADDONS_VERSION_FILE}")"
fi

if [ "${current_version}" = "${ADDONS_VERSION}" ] && [ -L "${ADDONS_CURRENT_LINK}" ]; then
  echo "Addons already at requested version ${ADDONS_VERSION}"
  exit 0
fi

archive_file="${TMP_DIR}/addons-${ADDONS_VERSION}.tar.gz"
extract_dir="${TMP_DIR}/extract-${ADDONS_VERSION}"
release_dir="${ADDONS_RELEASES_DIR}/${ADDONS_VERSION}"

download_archive() {
  if command -v wget >/dev/null 2>&1; then
    if [ -n "${ADDONS_USER}" ]; then
      wget -q --user="${ADDONS_USER}" --password="${ADDONS_PASSWORD}" -O "${archive_file}" "${ADDONS_ARCHIVE_URL}"
    else
      wget -q -O "${archive_file}" "${ADDONS_ARCHIVE_URL}"
    fi
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    if [ -n "${ADDONS_USER}" ]; then
      curl -fsSL -u "${ADDONS_USER}:${ADDONS_PASSWORD}" -o "${archive_file}" "${ADDONS_ARCHIVE_URL}"
    else
      curl -fsSL -o "${archive_file}" "${ADDONS_ARCHIVE_URL}"
    fi
    return 0
  fi

  echo "Neither wget nor curl is available" >&2
  exit 1
}

rm -rf "${extract_dir}" "${release_dir}.tmp"
mkdir -p "${extract_dir}"

download_archive

if [ -n "${ADDONS_SHA256}" ]; then
  echo "${ADDONS_SHA256}  ${archive_file}" | sha256sum -c -
fi

tar -xzf "${archive_file}" -C "${extract_dir}"

if [ ! -d "${extract_dir}/plugins" ] || [ ! -d "${extract_dir}/themes" ]; then
  echo "Addon archive must contain top-level plugins/ and themes/ directories" >&2
  exit 1
fi

mv "${extract_dir}" "${release_dir}.tmp"
rm -rf "${release_dir}"
mv "${release_dir}.tmp" "${release_dir}"

ln -sfn "${release_dir}" "${ADDONS_CURRENT_LINK}"
printf "%s\n" "${ADDONS_VERSION}" > "${ADDONS_VERSION_FILE}"

echo "Addon bundle synced to version ${ADDONS_VERSION}"
