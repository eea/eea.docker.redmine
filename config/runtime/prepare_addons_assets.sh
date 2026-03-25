#!/bin/bash
set -euo pipefail

REDMINE_PATH=${REDMINE_PATH:-/usr/src/redmine}
ADDONS_CURRENT_DIR=${ADDONS_CURRENT_DIR:-/addons/current}
PLUGINS_DIR=${PLUGINS_DIR:-${ADDONS_CURRENT_DIR}/plugins}
THEMES_DIR=${THEMES_DIR:-${ADDONS_CURRENT_DIR}/themes}
A1_THEME_ID=${A1_THEME_ID:-a1}
PUBLIC_DIR=${PUBLIC_DIR:-${REDMINE_PATH}/public}

ensure_file() {
  local destination="$1"
  shift
  local source
  local destination_dir

  destination_dir="$(dirname "${destination}")"
  if [ -f "${destination}" ]; then
    return 0
  fi
  if [ ! -d "${destination_dir}" ] && [ ! -w "$(dirname "${destination_dir}")" ]; then
    echo "Skipping asset materialization for ${destination} (parent not writable)"
    return 0
  fi
  if [ -d "${destination_dir}" ] && [ ! -w "${destination_dir}" ]; then
    echo "Skipping asset materialization for ${destination} (directory not writable)"
    return 0
  fi

  mkdir -p "${destination_dir}"

  for source in "$@"; do
    if [ -f "${source}" ]; then
      cp "${source}" "${destination}"
      return 0
    fi
  done

  : > "${destination}"
}

rewrite_css_urls() {
  local css

  for css in \
    "${PLUGINS_DIR}/redmine_contacts/assets/stylesheets/money.css" \
    "${PLUGINS_DIR}/redmineup/assets/stylesheets/money.css"; do
    if [ -f "${css}" ] && [ -w "${css}" ]; then
      sed -i \
        -e 's#\.\./images/money\.png#money.png#g' \
        -e 's#\.\./images/bullet_go\.png#bullet_go.png#g' \
        -e 's#\.\./images/bullet_end\.png#bullet_end.png#g' \
        -e 's#\.\./images/bullet_diamond\.png#bullet_diamond.png#g' \
        -e 's#\./bullet_go\.png#bullet_go.png#g' \
        -e 's#\./bullet_end\.png#bullet_end.png#g' \
        -e 's#\./bullet_diamond\.png#bullet_diamond.png#g' \
        "${css}"
    elif [ -f "${css}" ]; then
      echo "Skipping CSS rewrite for ${css} (read-only)"
    fi
  done

  for css in \
    "${PLUGINS_DIR}/redmine_contacts/assets/stylesheets/select2.css" \
    "${PLUGINS_DIR}/redmine_contacts/assets/stylesheets/calendars.css" \
    "${PLUGINS_DIR}/redmine_contacts_helpdesk/assets/stylesheets/helpdesk.css"; do
    if [ -f "${css}" ] && [ -w "${css}" ]; then
      sed -i \
        -e 's#\.\./images/vcard\.png#vcard.png#g' \
        -e 's#\.\./\.\./\.\./images/bullet_go\.png#bullet_go.png#g' \
        -e 's#\.\./\.\./\.\./images/bullet_end\.png#bullet_end.png#g' \
        -e 's#\.\./\.\./\.\./images/bullet_diamond\.png#bullet_diamond.png#g' \
        -e 's#\.\./\.\./\.\./loading\.gif#loading.gif#g' \
        "${css}"
    elif [ -f "${css}" ]; then
      echo "Skipping CSS rewrite for ${css} (read-only)"
    fi
  done

  css="${THEMES_DIR}/${A1_THEME_ID}/stylesheets/application.css"
  if [ -f "${css}" ] && [ -w "${css}" ]; then
    sed -i 's#/stylesheets/jquery/images/#jquery/#g' "${css}"
  elif [ -f "${css}" ]; then
    echo "Skipping CSS rewrite for ${css} (read-only)"
  fi
}

materialize_addon_assets() {
  ensure_file \
    "${PLUGINS_DIR}/additionals/assets/images/icons.svg" \
    "${REDMINE_PATH}/theme_overrides/a1/images/icons.svg"

  ensure_file \
    "${PLUGINS_DIR}/redmine_contacts_helpdesk/assets/images/loading.gif" \
    "${REDMINE_PATH}/theme_overrides/a1/images/loading.gif"

  ensure_file \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/money.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/money.png"

  ensure_file \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/bullet_go.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/bullet_go.png"

  ensure_file \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/bullet_end.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/bullet_end.png"

  ensure_file \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/bullet_diamond.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/bullet_diamond.png"

  ensure_file \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/vcard.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/vcard.png"

  # Legacy direct URLs still referenced by older theme/plugin code paths.
  ensure_file \
    "${PUBLIC_DIR}/plugin_assets/additionals/images/icons.svg" \
    "${PLUGINS_DIR}/additionals/assets/images/icons.svg" \
    "${REDMINE_PATH}/theme_overrides/a1/images/icons.svg"

  ensure_file \
    "${PUBLIC_DIR}/plugin_assets/redmine_contacts_helpdesk/loading.gif" \
    "${PLUGINS_DIR}/redmine_contacts_helpdesk/assets/images/loading.gif" \
    "${REDMINE_PATH}/theme_overrides/a1/images/loading.gif"

  ensure_file \
    "${PUBLIC_DIR}/plugin_assets/redmineup/bullet_go.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/bullet_go.png" \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/bullet_go.png"

  ensure_file \
    "${PUBLIC_DIR}/plugin_assets/redmineup/bullet_end.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/bullet_end.png" \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/bullet_end.png"

  ensure_file \
    "${PUBLIC_DIR}/plugin_assets/redmineup/bullet_diamond.png" \
    "${PLUGINS_DIR}/redmineup/assets/images/bullet_diamond.png" \
    "${PLUGINS_DIR}/redmine_contacts/assets/images/bullet_diamond.png"
}

rewrite_css_urls
materialize_addon_assets
echo "Addon asset fixes prepared in ${ADDONS_CURRENT_DIR}"
