#!/bin/bash
set -euo pipefail

REDMINE_PATH=${REDMINE_PATH:-/usr/src/redmine}
REDMINE_LOCAL_PATH=${REDMINE_LOCAL_PATH:-/var/local/redmine}

mkdir -p "${REDMINE_LOCAL_PATH}/github"

git clone https://github.com/eea/redmine-wiki_graphviz_plugin.git "${REDMINE_PATH}/plugins/wiki_graphviz_plugin"
cd "${REDMINE_PATH}/plugins/wiki_graphviz_plugin"
git checkout 33c07e45a6da51637418defa6a640acf8ca745d1
sed -i "s/^require[[:space:]]*'kconv'$/# Ruby 3.4 removed kconv; use String#encode below instead/" "${REDMINE_PATH}/plugins/wiki_graphviz_plugin/app/helpers/wiki_graphviz_helper.rb"
sed -i "s/t = t.toutf8/t = t.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')/" "${REDMINE_PATH}/plugins/wiki_graphviz_plugin/app/helpers/wiki_graphviz_helper.rb"
cd ..

git clone https://github.com/eea/redmine_wiki_backlinks.git "${REDMINE_PATH}/plugins/redmine_wiki_backlinks"
cd "${REDMINE_PATH}/plugins/redmine_wiki_backlinks"
git checkout be5749d0f258f9a3697342e6ced60af8534ed909
cd ..

git clone -b 0.3.5 https://github.com/agileware-jp/redmine_banner.git "${REDMINE_PATH}/plugins/redmine_banner"
git clone -b 3.4.0 https://github.com/alphanodes/additionals.git "${REDMINE_PATH}/plugins/additionals"
sed -i "s#require 'additionals/plugin_version'#require_relative 'lib/additionals/plugin_version'#" "${REDMINE_PATH}/plugins/additionals/init.rb"
git clone -b v1.5.1 https://github.com/mikitex70/redmine_drawio.git "${REDMINE_PATH}/plugins/redmine_drawio"
git clone -b 1.0.7 https://github.com/ncoders/redmine_local_avatars.git "${REDMINE_PATH}/plugins/redmine_local_avatars"

git clone https://github.com/eea/redmine_xls_export.git "${REDMINE_PATH}/plugins/redmine_xls_export"
cd "${REDMINE_PATH}/plugins/redmine_xls_export"
git checkout 087afa403b34a32313e7761cd018879f05f19e3c
cd ..

git clone -b master https://github.com/eea/redmine_entra_id.git "${REDMINE_PATH}/plugins/entra_id"
git clone -b 1.11.0 https://github.com/haru/redmine_ai_helper.git "${REDMINE_PATH}/plugins/redmine_ai_helper"
