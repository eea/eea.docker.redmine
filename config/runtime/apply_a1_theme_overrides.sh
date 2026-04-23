#!/bin/bash
set -euo pipefail

REDMINE_PATH=${REDMINE_PATH:-/usr/src/redmine}
A1_THEME_ID=${A1_THEME_ID:-a1}
THEMES_DIR=${THEMES_DIR:-}

if [ -z "${THEMES_DIR}" ]; then
  THEMES_DIR="${REDMINE_PATH}/public/themes"
  if [ -d "${REDMINE_PATH}/themes" ]; then
    THEMES_DIR="${REDMINE_PATH}/themes"
  fi
fi

overrides_root="${REDMINE_PATH}/theme_overrides/a1"
theme_root="${THEMES_DIR}/${A1_THEME_ID}"
css_src="${overrides_root}/stylesheets/taskman-backport-overrides.css"
js_src="${overrides_root}/javascripts/taskman-backport-overrides.js"
svg_src="${overrides_root}/svg/stop-hand.svg"
logo_src="${overrides_root}/images/logo/logo.png"
favicon_src="${overrides_root}/favicon/favicon.ico"
css_dst="${theme_root}/stylesheets/taskman-backport-overrides.css"
js_dst="${theme_root}/javascripts/taskman-backport-overrides.js"
svg_dst="${theme_root}/svg/stop-hand.svg"
logo_dst="${theme_root}/images/logo/logo.png"
logo_compat_dst="${theme_root}/logo/logo.png"
favicon_theme_dst="${theme_root}/favicon/favicon.ico"
favicon_public_dst="${REDMINE_PATH}/public/favicon.ico"
theme_css="${theme_root}/stylesheets/application.css"
theme_js="${theme_root}/javascripts/theme.js"
css_inline_begin="taskman-backport-overrides-inline-begin"
css_inline_end="taskman-backport-overrides-inline-end"
js_inline_begin="taskman-backport-overrides-inline-begin"
js_inline_end="taskman-backport-overrides-inline-end"

if [ ! -d "${overrides_root}" ] || [ ! -d "${theme_root}" ]; then
  exit 0
fi

mkdir -p "${theme_root}/stylesheets" "${theme_root}/javascripts" "${theme_root}/svg" "${theme_root}/images/logo" "${theme_root}/logo" "${theme_root}/favicon" "${REDMINE_PATH}/public"

if [ -f "${css_src}" ]; then
  cp "${css_src}" "${css_dst}"
  if [ -f "${theme_css}" ]; then
    sed -i "/${css_inline_begin}/,/${css_inline_end}/d" "${theme_css}"
    sed -i '/taskman-backport-overrides\.css/d' "${theme_css}"
    {
      printf "\n/* %s */\n" "${css_inline_begin}"
      cat "${css_src}"
      printf "\n/* %s */\n" "${css_inline_end}"
    } >> "${theme_css}"
  fi
fi

if [ -f "${js_src}" ]; then
  cp "${js_src}" "${js_dst}"
  if [ ! -f "${theme_js}" ]; then
    : > "${theme_js}"
  fi
  sed -i "/${js_inline_begin}/,/${js_inline_end}/d" "${theme_js}"
  {
    printf "\n/* %s */\n" "${js_inline_begin}"
    cat "${js_src}"
    printf "\n/* %s */\n" "${js_inline_end}"
  } >> "${theme_js}"

  if grep -q 'taskman-backport-overrides-loader' "${theme_js}"; then
    sed -i "/taskman-backport-overrides-loader/,/}());/d" "${theme_js}"
  fi
fi

if [ -f "${svg_src}" ]; then
  cp "${svg_src}" "${svg_dst}"
fi

if [ -f "${logo_src}" ]; then
  cp "${logo_src}" "${logo_dst}"
  cp "${logo_src}" "${logo_compat_dst}"
fi

if [ -f "${favicon_src}" ]; then
  cp "${favicon_src}" "${favicon_theme_dst}"
  cp "${favicon_src}" "${favicon_public_dst}"
fi
