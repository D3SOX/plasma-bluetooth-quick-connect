#!/usr/bin/env bash
# Packs the widget into a .plasmoid file for the KDE Store or manual installs.
set -euo pipefail
cd "$(dirname "$0")"

id=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Id"])')
version=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')
out="dist/${id}-${version}.plasmoid"

mkdir -p dist
rm -f "$out"
(cd package && zip -qr "../$out" .)
echo "$out"
