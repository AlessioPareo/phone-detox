#!/bin/sh
# Phone Detox: starts the app in your browser (Linux, and Mac from a terminal).
# Avvia l'app di Phone Detox nel browser (Linux, e Mac da terminale).
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is missing / Manca Python 3:"
  echo "  Ubuntu/Debian: sudo apt install python3"
  echo "  Fedora:        sudo dnf install python3"
  echo "  Mac:           xcode-select --install"
  printf 'Press Enter to close / Premi Invio per chiudere. '; read -r _; exit 1
fi
exec python3 ui/phone_detox_ui.py "$@"
