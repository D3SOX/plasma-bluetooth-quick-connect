#!/usr/bin/env bash
# Compiles every po/<lang>.po into the package, which is where Plasma looks for the widget's translations.
set -euo pipefail
cd "$(dirname "$0")/.."

id=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Id"])')

rm -rf package/contents/locale
for po in po/*.po; do
    [ -e "$po" ] || continue
    lang=$(basename "$po" .po)
    mkdir -p "package/contents/locale/$lang/LC_MESSAGES"
    msgfmt --check --output-file="package/contents/locale/$lang/LC_MESSAGES/plasma_applet_$id.mo" "$po"
done
