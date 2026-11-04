#!/bin/sh
# Lists every app on the phone with a verdict. Changes nothing.
#
#   sh candidates.sh [phone] [--tsv]
#
#   VERDICT  STATE  PACKAGE                            WHAT IT IS
#
#   never    the phone needs it (boot, calls, SMS, network, security) or Android always
#            keeps it on. Don't touch it.
#   useful   provides a feature you might use. Off only if you don't use it.
#   bloat    usually safe to turn off: ads, duplicates, manufacturer apps.
#   unknown  unknown. When in doubt, it stays on.
#   yours    you installed it: uninstall it normally from Settings.
#
# State: on, off, or removed (removed for the user, undo.sh brings it back).
# --tsv prints the raw table (verdict, state, package, Italian name, English name, Italian
# reason, English reason), separated by tabs: for programs.
# Messages in Italian or English: PD_LANG=it or en (default: from the system language).
set -e
. "$(dirname "$0")/lib.sh"

TARGET=; TSV=
for a in "$@"; do
  case "$a" in
    --tsv) TSV=1 ;;
    -*) say "Opzione sconosciuta: $a" "Unknown option: $a" >&2; exit 2 ;;
    *) TARGET=$a ;;
  esac
done
connect "$TARGET"
out=$(mktemp 2>/dev/null || mktemp -t phonedetox)
trap 'rm -f "$out"' EXIT
classify "$out"
if [ -n "$TSV" ]; then cat "$out"; exit 0; fi

awk -F'\t' -v it="$([ "$PD_LANG" = it ] && echo 1)" '{
  n = it ? $4 : $5; w = it ? $6 : $7
  if (n == "") n = $4
  if (w != "") n = (n == "" ? "(" w ")" : n " (" w ")")
  printf "%-8s %-8s %-48s %s\n", $1, $2, $3, n }' "$out"

count() { awk -F'\t' -v v="$1" '$1==v' "$out" | grep -c . || true; }
echo
echo "never $(count never) | useful $(count useful) | bloat $(count bloat) | unknown $(count unknown) | yours $(count yours)"
echo
say "bloat = di solito si può spegnere. unknown = sconosciuta: lasciala accesa se non sai cos'è." \
    "bloat = usually safe to turn off. unknown = leave it on unless you know what it is."
say "Prima di disattivare leggi docs/pulizia.md, e vai a gruppi di 5-10 app alla volta:" \
    "Before turning anything off read docs/cleanup.md, and go in groups of 5-10 apps:"
say "  sh disable.sh $TARGET <pacchetto> <pacchetto> ..." "  sh disable.sh $TARGET <package> <package> ..."
