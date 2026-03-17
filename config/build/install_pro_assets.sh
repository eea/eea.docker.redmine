#!/bin/bash
set -euo pipefail

REDMINE_PATH=${REDMINE_PATH:-/usr/src/redmine}
ADDONS_CFG="${REDMINE_PATH}/addons.cfg"
MANIFEST_SCRIPT="${REDMINE_PATH}/config/lib/addons_manifest.rb"

if [ ! -f "${ADDONS_CFG}" ]; then
  echo "addons.cfg is required at ${ADDONS_CFG}" >&2
  exit 1
fi
if [ ! -f "${MANIFEST_SCRIPT}" ]; then
  echo "addons manifest helper is required at ${MANIFEST_SCRIPT}" >&2
  exit 1
fi

manifest_cmd=(ruby "$MANIFEST_SCRIPT")

download_plugins() {
  local plugins_url="$1"
  local plugins_user="$2"
  local plugins_password="$3"
  local require_pro_plugins="$4"
  local addons_base_url="${ADDONS_BASE_URL:-${plugins_url%/plugins}}"

  if [ -n "$addons_base_url" ] && [ -n "$plugins_user" ] && [ -n "$plugins_password" ]; then
    mkdir -p /tmp/install_plugins
    local plugins_host plugins_home plugins_netrc
    plugins_host="$(echo "$addons_base_url" | awk -F/ '{print $3}')"
    plugins_home="$(mktemp -d /tmp/plugins-auth.XXXXXX)"
    plugins_netrc="${plugins_home}/.netrc"
    printf "machine %s login %s password %s\n" "$plugins_host" "$plugins_user" "$plugins_password" > "$plugins_netrc"
    chmod 600 "$plugins_netrc"

    while IFS=: read -r kind plugin_name plugin_location plugin_file; do
      [ "$kind" = "plugin" ] || continue
      archive="/tmp/install_plugins/$plugin_file"
      HOME="$plugins_home" wget -q --auth-no-challenge --netrc -O "$archive" "$addons_base_url/$plugin_location/$plugin_file"
      unzip -tqq "$archive"
      unzip -q -o "$archive" -d "${REDMINE_PATH}/plugins"
    done < <("${manifest_cmd[@]}" list)

    rm -f "$plugins_netrc"
    rm -rf "$plugins_home"
  elif [ "$require_pro_plugins" = "1" ]; then
    echo "REQUIRE_PRO_PLUGINS=1 but PLUGINS_URL/PLUGINS_USER/PLUGINS_PASSWORD are missing"
    exit 1
  else
    echo "Skipping pro plugins download at build-time (credentials not provided)"
  fi
}

validate_plugins() {
  local require_pro_plugins="$1"

  if [ "$require_pro_plugins" = "1" ]; then
    while IFS=: read -r kind plugin_name plugin_location plugin_file; do
      [ "$kind" = "plugin" ] || continue
      if [ ! -d "${REDMINE_PATH}/plugins/${plugin_name}" ]; then
        echo "Missing required plugin in built image: ${plugin_name} (${plugin_file})"
        exit 1
      fi
    done < <("${manifest_cmd[@]}" list)
  else
    while IFS=: read -r kind plugin_name plugin_location plugin_file; do
      [ "$kind" = "plugin" ] || continue
      if [ ! -d "${REDMINE_PATH}/plugins/${plugin_name}" ]; then
        echo "Optional plugin not present in image: ${plugin_name} (${plugin_file})"
      fi
    done < <("${manifest_cmd[@]}" list)
  fi
}

download_theme() {
  local plugins_url="$1"
  local plugins_user="$2"
  local plugins_password="$3"
  local a1_theme_url="$4"
  local a1_theme_user="$5"
  local a1_theme_password="$6"
  local a1_theme_sha256="$7"
  local a1_theme_zip="$8"
  local require_a1_theme="$9"
  local theme_id="${A1_THEME_ID:-a1}"
  local theme_manifest location archive
  local addons_base_url="${ADDONS_BASE_URL:-${plugins_url%/plugins}}"
  theme_manifest="$("${manifest_cmd[@]}" theme-location):$("${manifest_cmd[@]}" theme-archive)"
  location="${theme_manifest%%:*}"
  archive="${theme_manifest#*:}"
  [ -n "$archive" ] || archive="$a1_theme_zip"

  local theme_url
  theme_url="$a1_theme_url"
  if [ -z "$theme_url" ] && [ -n "$addons_base_url" ]; then
    theme_url="${addons_base_url}/${location:-themes}/${archive}"
  fi

  if [ -n "$theme_url" ]; then
    local themes_dir theme_host theme_home theme_netrc
    themes_dir="${REDMINE_PATH}/public/themes"
    if [ -d "${REDMINE_PATH}/themes" ]; then
      themes_dir="${REDMINE_PATH}/themes"
    fi
    mkdir -p "$themes_dir"
    echo "Downloading A1 theme into $themes_dir from $theme_url"

    if [ -n "$a1_theme_user" ] && [ -n "$a1_theme_password" ]; then
      theme_host="$(echo "$theme_url" | awk -F/ '{print $3}')"
      theme_home="$(mktemp -d /tmp/theme-auth.XXXXXX)"
      theme_netrc="${theme_home}/.netrc"
      printf "machine %s login %s password %s\n" "$theme_host" "$a1_theme_user" "$a1_theme_password" > "$theme_netrc"
      chmod 600 "$theme_netrc"
      HOME="$theme_home" wget -q --auth-no-challenge --netrc -O /tmp/a1-theme.zip "$theme_url"
      rm -f "$theme_netrc"
      rm -rf "$theme_home"
    elif [ -n "$plugins_user" ] && [ -n "$plugins_password" ]; then
      theme_host="$(echo "$theme_url" | awk -F/ '{print $3}')"
      theme_home="$(mktemp -d /tmp/theme-auth.XXXXXX)"
      theme_netrc="${theme_home}/.netrc"
      printf "machine %s login %s password %s\n" "$theme_host" "$plugins_user" "$plugins_password" > "$theme_netrc"
      chmod 600 "$theme_netrc"
      HOME="$theme_home" wget -q --auth-no-challenge --netrc -O /tmp/a1-theme.zip "$theme_url"
      rm -f "$theme_netrc"
      rm -rf "$theme_home"
    else
      wget -q -O /tmp/a1-theme.zip "$theme_url"
    fi

    unzip -tqq /tmp/a1-theme.zip
    if [ -n "$a1_theme_sha256" ]; then
      echo "$a1_theme_sha256  /tmp/a1-theme.zip" | sha256sum -c -
    fi
    unzip -q -o /tmp/a1-theme.zip -d "$themes_dir"
    rm -f /tmp/a1-theme.zip
  elif [ "$require_a1_theme" = "1" ]; then
    echo "REQUIRE_A1_THEME=1 but A1 theme URL/credentials are missing"
    exit 1
  else
    echo "Skipping A1 theme download at build-time (URL/credentials not provided)"
  fi
}

validate_theme() {
  local require_a1_theme="$1"

  if [ "$require_a1_theme" = "1" ]; then
    local themes_dir
    themes_dir="${REDMINE_PATH}/public/themes"
    if [ -d "${REDMINE_PATH}/themes" ]; then
      themes_dir="${REDMINE_PATH}/themes"
    fi
    test -d "${themes_dir}/a1"
  fi
}

download_plugins "${PLUGINS_URL:-}" "${PLUGINS_USER:-}" "${PLUGINS_PASSWORD:-}" "${REQUIRE_PRO_PLUGINS:-0}"
validate_plugins "${REQUIRE_PRO_PLUGINS:-0}"
download_theme "${PLUGINS_URL:-}" "${PLUGINS_USER:-}" "${PLUGINS_PASSWORD:-}" "${A1_THEME_URL:-}" "${A1_THEME_USER:-}" "${A1_THEME_PASSWORD:-}" "${A1_THEME_SHA256:-}" "${A1_THEME_ZIP:-a1_theme-4_1_2.zip}" "${REQUIRE_A1_THEME:-0}"
validate_theme "${REQUIRE_A1_THEME:-0}"
