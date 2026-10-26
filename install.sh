#!/usr/bin/env bash
# Installs or updates the widget for the current user.
set -euo pipefail
cd "$(dirname "$0")"

id=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Id"])')
installed=$(kpackagetool6 -t Plasma/Applet -l)
if grep -qx "$id" <<<"$installed"; then
    kpackagetool6 -t Plasma/Applet -u package
    echo "Updated. Restart Plasma to load the new version: systemctl --user restart plasma-plasmashell"
else
    kpackagetool6 -t Plasma/Applet -i package
fi
