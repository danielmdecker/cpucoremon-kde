#!/usr/bin/env bash
# Install / upgrade / remove the CPU Core Monitor plasmoid.
set -euo pipefail

ID="com.danielmdecker.cpucoremon"
PKG="$(cd "$(dirname "$0")" && pwd)/package"
ACTION="${1:-install}"

case "$ACTION" in
    install)
        if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$ID"; then
            echo "Upgrading existing $ID ..."
            kpackagetool6 -t Plasma/Applet -u "$PKG"
        else
            echo "Installing $ID ..."
            kpackagetool6 -t Plasma/Applet -i "$PKG"
        fi
        echo "Done. Add 'CPU Core Monitor' from the panel's 'Add Widgets' menu."
        echo "If it was already on the panel, reload Plasma:  kquitapp6 plasmashell && kstart plasmashell"
        ;;
    upgrade)
        kpackagetool6 -t Plasma/Applet -u "$PKG"
        ;;
    remove)
        kpackagetool6 -t Plasma/Applet -r "$ID"
        ;;
    *)
        echo "Usage: $0 [install|upgrade|remove]" >&2
        exit 1
        ;;
esac
