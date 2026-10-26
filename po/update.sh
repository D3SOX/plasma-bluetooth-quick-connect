#!/usr/bin/env bash
# Extracts the translatable strings into po/template.pot and merges them into every po/<lang>.po.
set -euo pipefail
cd "$(dirname "$0")/.."

id=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Id"])')
version=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')

find package -name '*.qml' | sort | xgettext \
    --files-from=- \
    --language=JavaScript \
    --from-code=UTF-8 \
    --keyword \
    --keyword=i18n:1 \
    --keyword=i18nc:1c,2 \
    --keyword=i18np:1,2 \
    --keyword=i18ncp:1c,2,3 \
    --package-name="plasma_applet_$id" \
    --package-version="$version" \
    --msgid-bugs-address="https://github.com/D3SOX/plasma-bluetooth-quick-connect/issues" \
    --output=po/template.pot
# Placeholders are KDE's %1, not JavaScript's %s, so don't let msgfmt check them as such.
sed -i 's/^#, javascript-format$/#, kde-format/' po/template.pot

for po in po/*.po; do
    [ -e "$po" ] || continue
    msgmerge --quiet --update --backup=none "$po" po/template.pot
done
